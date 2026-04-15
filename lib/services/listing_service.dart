import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../models/listing.dart';
import '../models/listing_offer.dart';
import '../models/user_transaction.dart';

enum MakeOfferResult {
  created,
  alreadyPending,
  listingUnavailable,
  ownListing,
}

class ListingService {
  ListingService({FirebaseFirestore? firestore, FirebaseStorage? storage})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _listingsRef =>
      _firestore.collection('listings');

  CollectionReference<Map<String, dynamic>> get _offersRef =>
      _firestore.collection('offers');

  CollectionReference<Map<String, dynamic>> get _reportsRef =>
      _firestore.collection('reports');

  CollectionReference<Map<String, dynamic>> get _contactUnlocksRef =>
      _firestore.collection('contact_unlocks');

  CollectionReference<Map<String, dynamic>> get _usersRef =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _notificationsRef =>
      _firestore.collection('notifications');

  String offerDocumentId({required String listingId, required String requesterId}) {
    return '${listingId}_$requesterId';
  }

  String contactPairDocumentId(String uidA, String uidB) {
    if (uidA.compareTo(uidB) <= 0) {
      return '${uidA}_$uidB';
    }
    return '${uidB}_$uidA';
  }

  Stream<List<Listing>> watchActiveListings() {
    return _listingsRef
        .where('status', isEqualTo: 'active')
        .limit(120)
        .snapshots()
        .map((snapshot) {
      final listings = snapshot.docs
          .map((doc) => Listing.fromFirestore(doc.id, doc.data()))
          .toList();

      listings.sort(_sortByRecent);
      return listings;
    });
  }

  Stream<List<Listing>> watchOwnerListings(String ownerId) {
    return _listingsRef
        .where('ownerId', isEqualTo: ownerId)
        .limit(200)
        .snapshots()
        .map((snapshot) {
      final listings = snapshot.docs
          .map((doc) => Listing.fromFirestore(doc.id, doc.data()))
          .toList();

      listings.sort(_sortByRecent);
      return listings;
    });
  }

  Stream<Listing?> watchListing(String listingId) {
    return _listingsRef.doc(listingId).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }
      return Listing.fromFirestore(snapshot.id, snapshot.data()!);
    });
  }

  Future<Listing?> getListingById(String listingId) async {
    final snapshot = await _listingsRef.doc(listingId).get();
    if (!snapshot.exists || snapshot.data() == null) {
      return null;
    }
    return Listing.fromFirestore(snapshot.id, snapshot.data()!);
  }

  Stream<ListingOffer?> watchMyOfferForListing({
    required String listingId,
    required String requesterId,
  }) {
    final docId = offerDocumentId(listingId: listingId, requesterId: requesterId);
    return _offersRef.doc(docId).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }
      return ListingOffer.fromFirestore(snapshot.id, snapshot.data()!);
    });
  }

  Future<ListingOffer?> getOfferById(String offerId) async {
    final snapshot = await _offersRef.doc(offerId).get();
    if (!snapshot.exists || snapshot.data() == null) {
      return null;
    }
    return ListingOffer.fromFirestore(snapshot.id, snapshot.data()!);
  }

  Stream<List<ListingOffer>> watchMyOffers(String requesterId) {
    return _offersRef
        .where('requesterId', isEqualTo: requesterId)
        .limit(300)
        .snapshots()
        .asyncMap((snapshot) async {
      var offers = snapshot.docs
          .map((doc) => ListingOffer.fromFirestore(doc.id, doc.data()))
          .toList();

      final listingIdsNeedingHydration = offers
          .where(
            (offer) =>
                offer.listingId.trim().isNotEmpty &&
                (offer.listingTitle.trim().isEmpty || !offer.hasListingTypeSnapshot),
          )
          .map((offer) => offer.listingId)
          .toSet()
          .toList();

      if (listingIdsNeedingHydration.isNotEmpty) {
        final listingSnapshots = await Future.wait(
          listingIdsNeedingHydration.map((listingId) => _listingsRef.doc(listingId).get()),
        );

        final titleByListingId = <String, String>{};
        final typeByListingId = <String, ListingType>{};
        for (final listingSnapshot in listingSnapshots) {
          final data = listingSnapshot.data();
          if (data == null) {
            continue;
          }
          final title = (data['title'] as String?)?.trim() ?? '';
          if (title.isNotEmpty) {
            titleByListingId[listingSnapshot.id] = title;
          }
          final typeRaw = (data['type'] as String?) ?? 'lend';
          typeByListingId[listingSnapshot.id] =
              typeRaw.trim().toLowerCase() == 'borrow'
                  ? ListingType.borrow
                  : ListingType.lend;
        }

        offers = offers.map((offer) {
          final hydratedTitle = titleByListingId[offer.listingId];
          final hydratedType = typeByListingId[offer.listingId];

          if (offer.listingTitle.trim().isNotEmpty &&
              offer.hasListingTypeSnapshot) {
            return offer;
          }
          return offer.copyWith(
            listingTitle:
                hydratedTitle == null || hydratedTitle.isEmpty
                    ? null
                    : hydratedTitle,
            listingType: hydratedType,
            hasListingTypeSnapshot: hydratedType != null,
          );
        }).toList();
      }

      offers.sort((a, b) {
        final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
        final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });

      return offers;
    });
  }

  Stream<List<ListingOffer>> watchIncomingOffersForListing({
    required String listingId,
    required String ownerId,
  }) {
    return _offersRef
        .where('listingId', isEqualTo: listingId)
        .where('ownerId', isEqualTo: ownerId)
        .limit(200)
        .snapshots()
        .map((snapshot) {
      final offers = snapshot.docs
          .map((doc) => ListingOffer.fromFirestore(doc.id, doc.data()))
          .toList();

      offers.sort((a, b) {
        final aPending = a.status == OfferStatus.pending ? 0 : 1;
        final bPending = b.status == OfferStatus.pending ? 0 : 1;
        if (aPending != bPending) {
          return aPending.compareTo(bPending);
        }

        final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
        final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });

      return offers;
    });
  }

  Stream<Map<String, int>> watchOfferCountsForOwner(String ownerId) {
    return _offersRef
        .where('ownerId', isEqualTo: ownerId)
        .limit(500)
        .snapshots()
        .map((snapshot) {
      final counts = <String, int>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final listingId = (data['listingId'] as String?) ?? '';
        final status = (data['status'] as String?) ?? 'pending';

        if (listingId.isEmpty || status != 'pending') {
          continue;
        }

        counts.update(listingId, (value) => value + 1, ifAbsent: () => 1);
      }
      return counts;
    });
  }

  Stream<List<UserTransaction>> watchUserTransactions(String userId) {
    final ownedAcceptedStream = _offersRef
        .where('ownerId', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .snapshots();
    final requestedAcceptedStream = _offersRef
        .where('requesterId', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .snapshots();

    final controller = StreamController<List<UserTransaction>>();
    QuerySnapshot<Map<String, dynamic>>? ownedSnapshot;
    QuerySnapshot<Map<String, dynamic>>? requestedSnapshot;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? ownedSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? requestedSub;

    Future<void> emitTransactions() async {
      try {
        final offerDocs = _collectAcceptedOfferDocs(
          ownedSnapshot: ownedSnapshot,
          requestedSnapshot: requestedSnapshot,
        );
        final transactions = await _buildTransactionsFromOfferDocs(
          userId: userId,
          offerDocs: offerDocs,
        );
        if (!controller.isClosed) {
          controller.add(transactions);
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller.onListen = () {
      ownedSub = ownedAcceptedStream.listen(
        (snapshot) {
          ownedSnapshot = snapshot;
          emitTransactions();
        },
        onError: controller.addError,
      );
      requestedSub = requestedAcceptedStream.listen(
        (snapshot) {
          requestedSnapshot = snapshot;
          emitTransactions();
        },
        onError: controller.addError,
      );
    };

    controller.onCancel = () async {
      await ownedSub?.cancel();
      await requestedSub?.cancel();
    };

    return controller.stream;
  }

  Future<List<UserTransaction>> fetchUserTransactions(String userId) async {
    final ownedAcceptedFuture = _offersRef
        .where('ownerId', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .get();
    final requestedAcceptedFuture = _offersRef
        .where('requesterId', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .get();

    final snapshots = await Future.wait([
      ownedAcceptedFuture,
      requestedAcceptedFuture,
    ]);

    final offerDocs = _collectAcceptedOfferDocs(
      ownedSnapshot: snapshots[0],
      requestedSnapshot: snapshots[1],
    );

    return _buildTransactionsFromOfferDocs(
      userId: userId,
      offerDocs: offerDocs,
    );
  }

  Future<String> createListing({
    required String ownerId,
    required String ownerDisplayName,
    required String title,
    required String description,
    required String category,
    required ListingType type,
    String? ownerPhotoUrl,
    String? existingImageUrl,
    Duration? urgentDuration,
    XFile? image,
  }) async {
    await _ensureUrgentAllowed(
      ownerId: ownerId,
      type: type,
      urgentDuration: urgentDuration,
    );

    final docRef = _listingsRef.doc();
    String? imageUrl = (existingImageUrl?.trim().isNotEmpty ?? false)
        ? existingImageUrl!.trim()
        : null;

    if (image != null) {
      imageUrl = await _uploadListingImage(
        ownerId: ownerId,
        listingId: docRef.id,
        image: image,
      );
    }

    final isUrgentBorrow = type == ListingType.borrow && urgentDuration != null;
    final urgentUntil = isUrgentBorrow
        ? Timestamp.fromDate(DateTime.now().add(urgentDuration))
        : null;

    final payload = <String, dynamic>{
      'ownerId': ownerId,
      'ownerDisplayName': ownerDisplayName.trim().isEmpty
          ? 'Columbia Student'
          : ownerDisplayName.trim(),
      'ownerPhotoUrl': ownerPhotoUrl,
      'title': title.trim(),
      'description': description.trim(),
      'category': category.trim(),
      'type': type.name,
      'status': 'active',
      'imageUrl': imageUrl,
      'urgent': isUrgentBorrow,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (urgentUntil != null) {
      payload['urgentUntil'] = urgentUntil;
    }

    await docRef.set(payload);

    return docRef.id;
  }

  Future<void> markListingReturned({
    required String listingId,
    required String ownerId,
  }) async {
    final listingRef = _listingsRef.doc(listingId);
    String acceptedOfferId = '';
    String acceptedRequesterId = '';
    String listingTitle = '';

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(listingRef);
      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('Listing not found.');
      }

      final data = snapshot.data()!;
      if ((data['ownerId'] as String?) != ownerId) {
        throw StateError('Only the owner can mark this listing as returned.');
      }

      final currentStatus = (data['status'] as String?) ?? 'active';
      final listingType = (data['type'] as String?) ?? 'lend';
      acceptedOfferId = (data['acceptedOfferId'] as String?)?.trim() ?? '';
      acceptedRequesterId = (data['acceptedRequesterId'] as String?)?.trim() ?? '';
      listingTitle = ((data['title'] as String?) ?? '').trim();
      final canMarkReturned = currentStatus == 'sold' ||
          (currentStatus == 'archived' && acceptedOfferId.isNotEmpty);

      if (listingType != 'lend') {
        throw StateError('Only lend listings can be marked as returned.');
      }

      if (!canMarkReturned) {
        throw StateError('Only in-use listings can be marked as returned.');
      }

      transaction.update(listingRef, {
        'status': 'archived',
        'acceptedOfferId': FieldValue.delete(),
        'acceptedRequesterId': FieldValue.delete(),
        'archivedFromSold': FieldValue.delete(),
        'returnedFromMatch': true,
        'pickedUpAt': FieldValue.delete(),
        'returnDueAt': FieldValue.delete(),
        'matchedAt': FieldValue.delete(),
        'returnedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (acceptedRequesterId.isNotEmpty) {
      await _writeNotification(
        recipientId: acceptedRequesterId,
        actorId: ownerId,
        type: 'offer_declined',
        listingId: listingId,
        offerId: acceptedOfferId.isEmpty ? null : acceptedOfferId,
        title: 'Item returned',
        body:
            '${listingTitle.isEmpty ? 'This item' : listingTitle} was marked as returned and the match is now closed.',
      );
    }
  }

  Future<String> relistFromListing({
    required String sourceListingId,
    required String ownerId,
  }) async {
    final sourceSnapshot = await _listingsRef.doc(sourceListingId).get();
    if (!sourceSnapshot.exists || sourceSnapshot.data() == null) {
      throw StateError('Original listing not found.');
    }

    final sourceData = sourceSnapshot.data()!;
    final sourceOwnerId = (sourceData['ownerId'] as String?) ?? '';
    if (sourceOwnerId != ownerId) {
      throw StateError('Only the owner can relist this item.');
    }

    final title = ((sourceData['title'] as String?) ?? '').trim();
    if (title.isEmpty) {
      throw StateError('Cannot relist a listing without a title.');
    }

    final ownerDisplayName =
        ((sourceData['ownerDisplayName'] as String?) ?? '').trim();
    final ownerPhotoUrl = sourceData['ownerPhotoUrl'] as String?;
    final description = ((sourceData['description'] as String?) ?? '').trim();
    final category = ((sourceData['category'] as String?) ?? 'Other').trim();
    final rawType = ((sourceData['type'] as String?) ?? 'lend').trim().toLowerCase();
    final type = rawType == 'borrow' ? ListingType.borrow : ListingType.lend;
    final existingImageUrl = (sourceData['imageUrl'] as String?)?.trim();

    final newListingId = await createListing(
      ownerId: ownerId,
      ownerDisplayName:
          ownerDisplayName.isEmpty ? 'Columbia Student' : ownerDisplayName,
      ownerPhotoUrl: ownerPhotoUrl,
      title: title,
      description: description,
      category: category.isEmpty ? 'Other' : category,
      type: type,
      existingImageUrl:
          existingImageUrl?.isEmpty == true ? null : existingImageUrl,
      urgentDuration: null,
      image: null,
    );

    await _listingsRef.doc(newListingId).update({
      'relistedFromListingId': sourceListingId,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return newListingId;
  }

  Future<void> updateListing({
    required String listingId,
    required String ownerId,
    required String ownerDisplayName,
    required String title,
    required String description,
    required String category,
    required ListingType type,
    String? ownerPhotoUrl,
    Duration? urgentDuration,
    XFile? image,
  }) async {
    await _ensureUrgentAllowed(
      ownerId: ownerId,
      type: type,
      urgentDuration: urgentDuration,
    );

    final docRef = _listingsRef.doc(listingId);
    final snapshot = await docRef.get();

    if (!snapshot.exists || snapshot.data() == null) {
      throw StateError('Listing not found.');
    }

    final data = snapshot.data()!;
    if ((data['ownerId'] as String?) != ownerId) {
      throw StateError('Only the owner can edit this listing.');
    }

    var imageUrl = data['imageUrl'] as String?;
    if (image != null) {
      imageUrl = await _uploadListingImage(
        ownerId: ownerId,
        listingId: listingId,
        image: image,
      );
    }

    final isUrgentBorrow = type == ListingType.borrow && urgentDuration != null;
    final urgentUntil = isUrgentBorrow
        ? Timestamp.fromDate(DateTime.now().add(urgentDuration))
        : null;

    await docRef.update({
      'ownerDisplayName': ownerDisplayName.trim().isEmpty
          ? 'Columbia Student'
          : ownerDisplayName.trim(),
      'ownerPhotoUrl': ownerPhotoUrl,
      'title': title.trim(),
      'description': description.trim(),
      'category': category.trim(),
      'type': type.name,
      'imageUrl': imageUrl,
      'urgent': isUrgentBorrow,
      'urgentUntil': urgentUntil ?? FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setListingArchived({
    required String listingId,
    required String ownerId,
    required bool archived,
  }) async {
    final listingRef = _listingsRef.doc(listingId);
    String matchedRequesterId = '';
    String matchedOfferId = '';
    bool hadMatchedState = false;

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(listingRef);
      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('Listing not found.');
      }

      final data = snapshot.data()!;
      if ((data['ownerId'] as String?) != ownerId) {
        throw StateError('Only the owner can archive this listing.');
      }

      final currentStatus = (data['status'] as String?) ?? 'active';
      final returnedFromMatch =
          (data['returnedFromMatch'] as bool? ?? false) ||
          (currentStatus == 'archived' && data['returnedAt'] is Timestamp);
      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (archived) {
        final isInUse = currentStatus == 'sold' && data['pickedUpAt'] is Timestamp;
        if (isInUse) {
          throw StateError('In-use listings cannot be archived.');
        }
        hadMatchedState =
            currentStatus == 'sold' ||
            ((data['acceptedOfferId'] as String?)?.trim().isNotEmpty ?? false);
        matchedOfferId = (data['acceptedOfferId'] as String?)?.trim() ?? '';
        matchedRequesterId =
            (data['acceptedRequesterId'] as String?)?.trim() ?? '';
        updateData['status'] = 'archived';
        updateData['acceptedOfferId'] = FieldValue.delete();
        updateData['acceptedRequesterId'] = FieldValue.delete();
        updateData['matchedAt'] = FieldValue.delete();
        updateData['pickedUpAt'] = FieldValue.delete();
        updateData['returnDueAt'] = FieldValue.delete();
        updateData['returnedAt'] = FieldValue.delete();
        updateData['archivedFromSold'] = FieldValue.delete();
        updateData['returnedFromMatch'] = FieldValue.delete();
      } else {
        if (currentStatus == 'archived') {
          if (returnedFromMatch) {
            throw StateError(
              'Returned listings cannot be unarchived. Use relist instead.',
            );
          }
          updateData['status'] = 'active';
        }
        updateData['archivedFromSold'] = FieldValue.delete();
        updateData['returnedFromMatch'] = FieldValue.delete();
      }

      transaction.update(listingRef, updateData);
    });

    if (!archived) {
      return;
    }

    while (true) {
      final offersSnapshot = await _offersRef
          .where('listingId', isEqualTo: listingId)
          .where('ownerId', isEqualTo: ownerId)
          .limit(500)
          .get();

      if (offersSnapshot.docs.isEmpty) {
        break;
      }

      final batch = _firestore.batch();
      for (final doc in offersSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    final resolvedMatchedRequesterId = matchedRequesterId.isNotEmpty
        ? matchedRequesterId
        : _deriveRequesterIdFromOfferId(
            listingId: listingId,
            offerId: matchedOfferId,
          );

    if (hadMatchedState && resolvedMatchedRequesterId.isNotEmpty) {
      final pairId = contactPairDocumentId(ownerId, resolvedMatchedRequesterId);
      try {
        await _contactUnlocksRef.doc(pairId).delete();
      } catch (_) {
        // Best-effort cleanup. Listing archive should still succeed.
      }
    }
  }

  Future<MakeOfferResult> makeOffer({
    required String listingId,
    required String requesterId,
    required bool liabilityAccepted,
  }) async {
    if (!liabilityAccepted) {
      return MakeOfferResult.listingUnavailable;
    }

    final txResult =
        await _firestore.runTransaction<_MakeOfferTransactionResult>((transaction) async {
      final listingRef = _listingsRef.doc(listingId);
      final listingSnapshot = await transaction.get(listingRef);

      if (!listingSnapshot.exists || listingSnapshot.data() == null) {
        return const _MakeOfferTransactionResult(
          result: MakeOfferResult.listingUnavailable,
        );
      }

      final listingData = listingSnapshot.data()!;
      final status = (listingData['status'] as String?) ?? 'active';
      final ownerId = (listingData['ownerId'] as String?) ?? '';
      final listingTitle = (listingData['title'] as String?)?.trim();

      if (status != 'active') {
        return const _MakeOfferTransactionResult(
          result: MakeOfferResult.listingUnavailable,
        );
      }

      if (ownerId == requesterId || ownerId.isEmpty) {
        return const _MakeOfferTransactionResult(
          result: MakeOfferResult.ownListing,
        );
      }

      final offerRef = _offersRef.doc(
        offerDocumentId(listingId: listingId, requesterId: requesterId),
      );
      final offerSnapshot = await transaction.get(offerRef);

      if (offerSnapshot.exists && offerSnapshot.data() != null) {
        final existingStatus = (offerSnapshot.data()!['status'] as String?) ?? '';
        if (existingStatus == 'pending' || existingStatus == 'accepted') {
          return const _MakeOfferTransactionResult(
            result: MakeOfferResult.alreadyPending,
          );
        }
      }

      transaction.set(offerRef, {
        'listingId': listingId,
        'listingTitle': listingTitle ?? '',
        'listingType': (listingData['type'] as String?) ?? 'lend',
        'ownerId': ownerId,
        'requesterId': requesterId,
        'status': 'pending',
        'pickedUpAt': FieldValue.delete(),
        'returnDueAt': FieldValue.delete(),
        'returnedAt': FieldValue.delete(),
        'liabilityAccepted': true,
        'liabilityAcceptedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return _MakeOfferTransactionResult(
        result: MakeOfferResult.created,
        ownerId: ownerId,
        listingTitle: listingTitle,
      );
    });

    if (txResult.result == MakeOfferResult.created &&
        txResult.ownerId != null &&
        txResult.ownerId!.isNotEmpty) {
      await _writeNotification(
        recipientId: txResult.ownerId!,
        actorId: requesterId,
        type: 'offer_received',
        listingId: listingId,
        offerId: offerDocumentId(listingId: listingId, requesterId: requesterId),
        title: 'New offer',
        body:
            'Someone made an offer on ${txResult.listingTitle?.isNotEmpty == true ? txResult.listingTitle : 'your listing'}.',
      );
    }

    return txResult.result;
  }

  Future<void> acceptIncomingOffer({
    required String listingId,
    required String offerId,
    required String ownerId,
  }) async {
    final listingRef = _listingsRef.doc(listingId);
    final acceptedOfferRef = _offersRef.doc(offerId);
    final acceptedRequesterId = _deriveRequesterIdFromOfferId(
      listingId: listingId,
      offerId: offerId,
    );
    if (acceptedRequesterId.isEmpty) {
      throw StateError('Offer requester is missing.');
    }

    String listingTitle = '';

    try {
      final listingSnapshot = await listingRef.get();
      final listingData = listingSnapshot.data();
      if (listingData != null) {
        listingTitle = (listingData['title'] as String?)?.trim() ?? '';
      }
    } catch (_) {
      // Title hydration is best-effort for notifications only.
    }

    final batch = _firestore.batch();
    batch.update(acceptedOfferRef, {
      'status': 'accepted',
      'pickedUpAt': FieldValue.delete(),
      'returnDueAt': FieldValue.delete(),
      'returnedAt': FieldValue.delete(),
      'acceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(listingRef, {
      'status': 'sold',
      'acceptedOfferId': offerId,
      'acceptedRequesterId': acceptedRequesterId,
      'urgent': false,
      'urgentUntil': FieldValue.delete(),
      'archivedFromSold': FieldValue.delete(),
      'returnedFromMatch': FieldValue.delete(),
      'pickedUpAt': FieldValue.delete(),
      'returnDueAt': FieldValue.delete(),
      'returnedAt': FieldValue.delete(),
      'matchedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    if (acceptedRequesterId.isNotEmpty) {
      await _upsertContactUnlock(
        ownerId: ownerId,
        requesterId: acceptedRequesterId,
        listingId: listingId,
        offerId: offerId,
      );
    }

    try {
      final pendingOffersSnapshot = await _offersRef
          .where('listingId', isEqualTo: listingId)
          .where('ownerId', isEqualTo: ownerId)
          .get();

      if (pendingOffersSnapshot.docs.isNotEmpty) {
        final batch = _firestore.batch();
        final declinedNotifications = <({String requesterId, String offerId})>[];
        for (final doc in pendingOffersSnapshot.docs) {
          final data = doc.data();
          if ((data['status'] as String?) != 'pending') {
            continue;
          }
          if (doc.id == offerId) {
            continue;
          }
          final declinedRequesterId = (data['requesterId'] as String?) ?? '';
          batch.update(doc.reference, {
            'status': 'declined',
            'declinedReason': 'accepted_other_offer',
            'updatedAt': FieldValue.serverTimestamp(),
          });

          if (declinedRequesterId.isNotEmpty) {
            declinedNotifications.add(
              (requesterId: declinedRequesterId, offerId: doc.id),
            );
          }
        }

        await batch.commit();

        for (final item in declinedNotifications) {
          await _writeNotification(
            recipientId: item.requesterId,
            actorId: ownerId,
            type: 'offer_declined',
            listingId: listingId,
            offerId: item.offerId,
            title: 'Offer declined',
            body:
                'Your offer for ${listingTitle.isEmpty ? 'a listing' : listingTitle} was declined.',
          );
        }
      }
    } catch (_) {
      // Auto-declining other pending offers is best-effort and should not
      // revert a successful accept.
    }

    if (acceptedRequesterId.isNotEmpty) {
      await _writeNotification(
        recipientId: acceptedRequesterId,
        actorId: ownerId,
        type: 'offer_accepted',
        listingId: listingId,
        offerId: offerId,
        title: 'Offer accepted',
        body:
            'Your offer for ${listingTitle.isEmpty ? 'a listing' : listingTitle} was accepted. Contact info is now available.',
      );
    }
  }

  Future<void> declineIncomingOffer({
    required String offerId,
    required String ownerId,
  }) async {
    final offerRef = _offersRef.doc(offerId);
    String requesterId = '';
    String listingId = '';

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(offerRef);
      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('Offer no longer exists.');
      }

      final data = snapshot.data()!;
      if ((data['ownerId'] as String?) != ownerId) {
        throw StateError('Only the owner can decline this offer.');
      }
      requesterId = (data['requesterId'] as String?) ?? '';
      listingId = (data['listingId'] as String?) ?? '';

      final status = (data['status'] as String?) ?? 'pending';
      if (status != 'pending') {
        throw StateError('Only pending offers can be declined.');
      }

      transaction.update(offerRef, {
        'status': 'declined',
        'declinedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (requesterId.isNotEmpty) {
      await _writeNotification(
        recipientId: requesterId,
        actorId: ownerId,
        type: 'offer_declined',
        listingId: listingId,
        offerId: offerId,
        title: 'Offer declined',
        body: 'Your offer was declined.',
      );
    }
  }

  Future<void> cancelPendingOffer({
    required String offerId,
    required String requesterId,
  }) async {
    final offerRef = _offersRef.doc(offerId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(offerRef);
      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError('Offer no longer exists.');
      }

      final data = snapshot.data()!;
      if ((data['requesterId'] as String?) != requesterId) {
        throw StateError('Only the requester can cancel this offer.');
      }

      final status = (data['status'] as String?) ?? 'pending';
      if (status != 'pending') {
        throw StateError('Only pending offers can be cancelled.');
      }

      transaction.delete(offerRef);
    });
  }

  Future<void> markOfferPickedUp({
    required String offerId,
    required String actorId,
    required DateTime returnDueAt,
  }) async {
    final offerRef = _offersRef.doc(offerId);

    await _firestore.runTransaction((transaction) async {
      final offerSnapshot = await transaction.get(offerRef);
      if (!offerSnapshot.exists || offerSnapshot.data() == null) {
        throw StateError('Offer no longer exists.');
      }

      final offerData = offerSnapshot.data()!;
      if ((offerData['status'] as String?) != 'accepted') {
        throw StateError('Only accepted offers can be marked picked up.');
      }
      if (offerData['pickedUpAt'] is Timestamp) {
        throw StateError('This match is already marked as picked up.');
      }

      final listingId = (offerData['listingId'] as String?) ?? '';
      if (listingId.isEmpty) {
        throw StateError('Listing reference missing on this offer.');
      }

      final listingRef = _listingsRef.doc(listingId);
      final listingSnapshot = await transaction.get(listingRef);
      if (!listingSnapshot.exists || listingSnapshot.data() == null) {
        throw StateError('Listing not found.');
      }

      final listingData = listingSnapshot.data()!;
      final listingType = (listingData['type'] as String?) ?? 'lend';
      final requesterId = (offerData['requesterId'] as String?) ?? '';
      final lenderId = listingType == 'borrow'
          ? requesterId
          : ((listingData['ownerId'] as String?) ?? '');

      if (lenderId != actorId) {
        throw StateError('Only the lender can mark pickup.');
      }

      final acceptedRequesterId = (listingData['acceptedRequesterId'] as String?)?.trim();
      if ((listingData['acceptedOfferId'] as String?) != offerId ||
          (acceptedRequesterId != null &&
              acceptedRequesterId.isNotEmpty &&
              acceptedRequesterId != requesterId) ||
          (listingData['status'] as String?) != 'sold') {
        throw StateError('This offer is not the active matched lender.');
      }
      if (listingData['pickedUpAt'] is Timestamp) {
        throw StateError('This match is already marked as picked up.');
      }

      transaction.update(offerRef, {
        'pickedUpAt': FieldValue.serverTimestamp(),
        'returnDueAt': Timestamp.fromDate(returnDueAt),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(listingRef, {
        'acceptedRequesterId': requesterId,
        'pickedUpAt': FieldValue.serverTimestamp(),
        'returnDueAt': Timestamp.fromDate(returnDueAt),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> markOfferReturned({
    required String offerId,
    required String actorId,
  }) async {
    final offerRef = _offersRef.doc(offerId);
    String listingId = '';
    String borrowerId = '';
    String listingTitle = '';

    await _firestore.runTransaction((transaction) async {
      final offerSnapshot = await transaction.get(offerRef);
      if (!offerSnapshot.exists || offerSnapshot.data() == null) {
        throw StateError('Offer no longer exists.');
      }

      final offerData = offerSnapshot.data()!;
      if ((offerData['status'] as String?) != 'accepted') {
        throw StateError('Only accepted offers can be marked returned.');
      }

      final pickedUpAt = offerData['pickedUpAt'];
      if (pickedUpAt is! Timestamp) {
        throw StateError('Mark as picked up before marking returned.');
      }
      if (offerData['returnedAt'] is Timestamp) {
        throw StateError('This match is already marked returned.');
      }

      listingId = (offerData['listingId'] as String?) ?? '';
      if (listingId.isEmpty) {
        throw StateError('Listing reference missing on this offer.');
      }

      final listingRef = _listingsRef.doc(listingId);
      final listingSnapshot = await transaction.get(listingRef);
      if (!listingSnapshot.exists || listingSnapshot.data() == null) {
        throw StateError('Listing not found.');
      }

      final listingData = listingSnapshot.data()!;
      final listingType = (listingData['type'] as String?) ?? 'lend';
      final requesterId = (offerData['requesterId'] as String?) ?? '';
      final ownerId = (listingData['ownerId'] as String?) ?? '';
      final lenderId = listingType == 'borrow' ? requesterId : ownerId;
      borrowerId = listingType == 'borrow' ? ownerId : requesterId;

      if (lenderId != actorId) {
        throw StateError('Only the lender can mark this item returned.');
      }

      final acceptedRequesterId = (listingData['acceptedRequesterId'] as String?)?.trim();
      if ((listingData['acceptedOfferId'] as String?) != offerId ||
          (acceptedRequesterId != null &&
              acceptedRequesterId.isNotEmpty &&
              acceptedRequesterId != requesterId) ||
          (listingData['status'] as String?) != 'sold') {
        throw StateError('This offer is not the active matched lender.');
      }

      listingTitle = (listingData['title'] as String?)?.trim() ?? '';

      transaction.update(offerRef, {
        'returnedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(listingRef, {
        'status': 'archived',
        'acceptedOfferId': null,
        'acceptedRequesterId': null,
        'urgent': false,
        'urgentUntil': FieldValue.delete(),
        'archivedFromSold': FieldValue.delete(),
        'returnedFromMatch': true,
        'pickedUpAt': FieldValue.delete(),
        'returnDueAt': FieldValue.delete(),
        'matchedAt': FieldValue.delete(),
        'returnedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (borrowerId.isNotEmpty) {
      await _writeNotification(
        recipientId: borrowerId,
        actorId: actorId,
        type: 'offer_declined',
        listingId: listingId,
        offerId: offerId,
        title: 'Item returned',
        body:
            '${listingTitle.isEmpty ? 'Your matched item' : listingTitle} was marked as returned by the lender.',
      );
    }
  }

  Future<void> markBorrowOfferPickedUp({
    required String offerId,
    required String requesterId,
    required DateTime returnDueAt,
  }) {
    return markOfferPickedUp(
      offerId: offerId,
      actorId: requesterId,
      returnDueAt: returnDueAt,
    );
  }

  Future<void> markBorrowOfferReturned({
    required String offerId,
    required String requesterId,
  }) {
    return markOfferReturned(
      offerId: offerId,
      actorId: requesterId,
    );
  }

  Future<void> submitListingReport({
    required String listingId,
    required String reporterId,
    required String reason,
    String? reportedUserId,
    String? listingTitle,
  }) async {
    final normalizedReportedUserId = (reportedUserId ?? '').trim();
    await _reportsRef.add({
      'reportType': 'report_listing',
      'targetId': listingId,
      'listingId': listingId,
      'reporterId': reporterId,
      'reason': reason.trim(),
      'reportedUserId': normalizedReportedUserId.isEmpty
          ? null
          : normalizedReportedUserId,
      'listingTitle': (listingTitle ?? '').trim(),
      'status': 'open',
      'source': 'app',
      'updatedAt': FieldValue.serverTimestamp(),
      'resolvedAt': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> submitUserReport({
    required String reportedUserId,
    required String reporterId,
    required String reason,
    String? reportedDisplayName,
  }) async {
    await _reportsRef.add({
      'reportType': 'report_user',
      'targetId': reportedUserId,
      'reportedUserId': reportedUserId,
      'reporterId': reporterId,
      'reason': reason.trim(),
      'reportedDisplayName': (reportedDisplayName ?? '').trim(),
      'status': 'open',
      'source': 'app',
      'updatedAt': FieldValue.serverTimestamp(),
      'resolvedAt': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> seedDemoListings({
    required String ownerId,
    required String ownerDisplayName,
    String? ownerPhotoUrl,
  }) async {
    final normalizedName =
        ownerDisplayName.trim().isEmpty ? 'Columbia Student' : ownerDisplayName.trim();

    final demoListings = <Map<String, dynamic>>[
      {
        'id': 'demo_${ownerId}_lend_lamp',
        'title': 'Desk Lamp',
        'description': 'Great for late-night study sessions in the dorm.',
        'category': 'Dorm Essentials',
        'type': 'lend',
        'status': 'active',
        'urgent': false,
      },
      {
        'id': 'demo_${ownerId}_borrow_calculator',
        'title': 'Need TI-84 Calculator',
        'description': 'Need one for a quiz this afternoon.',
        'category': 'School Supplies',
        'type': 'borrow',
        'status': 'active',
        'urgent': true,
        'urgentUntil': Timestamp.fromDate(
          DateTime.now().add(const Duration(hours: 1)),
        ),
      },
      {
        'id': 'demo_${ownerId}_lend_foldable_table',
        'title': 'Foldable Side Table',
        'description': 'Small and easy to carry, useful for temporary setups.',
        'category': 'Outdoors',
        'type': 'lend',
        'status': 'active',
        'urgent': false,
      },
    ];

    final batch = _firestore.batch();
    for (final entry in demoListings) {
      final docId = entry['id'] as String;
      final ref = _listingsRef.doc(docId);

      final data = <String, dynamic>{
        'ownerId': ownerId,
        'ownerDisplayName': normalizedName,
        'ownerPhotoUrl': ownerPhotoUrl,
        'title': entry['title'],
        'description': entry['description'],
        'category': entry['category'],
        'type': entry['type'],
        'status': entry['status'],
        'urgent': entry['urgent'],
        'imageUrl': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (entry['urgentUntil'] != null) {
        data['urgentUntil'] = entry['urgentUntil'];
      }

      batch.set(ref, data, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<String> _uploadListingImage({
    required String ownerId,
    required String listingId,
    required XFile image,
  }) async {
    final extension = image.path.split('.').last.toLowerCase();
    final fileName = '${listingId}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final ref = _storage.ref().child('listings/$ownerId/$fileName');

    final uploadTask = await ref.putFile(
      File(image.path),
      SettableMetadata(contentType: _fileContentType(image.path)),
    );

    return uploadTask.ref.getDownloadURL();
  }

  int _sortByRecent(Listing a, Listing b) {
    final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
    final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
    return bTime.compareTo(aTime);
  }

  String _fileContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  DateTime? _timestampToDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _collectAcceptedOfferDocs({
    required QuerySnapshot<Map<String, dynamic>>? ownedSnapshot,
    required QuerySnapshot<Map<String, dynamic>>? requestedSnapshot,
  }) {
    final offerDocsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    if (ownedSnapshot != null) {
      for (final doc in ownedSnapshot.docs) {
        offerDocsById[doc.id] = doc;
      }
    }

    if (requestedSnapshot != null) {
      for (final doc in requestedSnapshot.docs) {
        offerDocsById[doc.id] = doc;
      }
    }

    return offerDocsById.values.toList();
  }

  Future<List<UserTransaction>> _buildTransactionsFromOfferDocs({
    required String userId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> offerDocs,
  }) async {
    if (offerDocs.isEmpty) {
      return const <UserTransaction>[];
    }

    final listingIds = <String>{};
    for (final doc in offerDocs) {
      final listingId = (doc.data()['listingId'] as String?) ?? '';
      if (listingId.isNotEmpty) {
        listingIds.add(listingId);
      }
    }

    final listingSnapshots = await Future.wait(
      listingIds.map((listingId) => _listingsRef.doc(listingId).get()),
    );

    final listingById = <String, Listing>{};
    for (final listingSnapshot in listingSnapshots) {
      if (!listingSnapshot.exists || listingSnapshot.data() == null) {
        continue;
      }
      listingById[listingSnapshot.id] = Listing.fromFirestore(
        listingSnapshot.id,
        listingSnapshot.data()!,
      );
    }

    final transactions = <UserTransaction>[];
    for (final offerDoc in offerDocs) {
      final data = offerDoc.data();
      final listingId = (data['listingId'] as String?) ?? '';
      final listing = listingById[listingId];
      if (listing == null) {
        continue;
      }

      final isOwner = (data['ownerId'] as String?) == userId;
      final isLendListing = listing.type == ListingType.lend;
      final role = isLendListing
          ? (isOwner ? TransactionRole.lent : TransactionRole.borrowed)
          : (isOwner ? TransactionRole.borrowed : TransactionRole.lent);
      final counterpartyId = isOwner
          ? ((data['requesterId'] as String?) ?? '')
          : ((data['ownerId'] as String?) ?? '');
      final acceptedAt = _timestampToDateTime(data['acceptedAt']) ??
          _timestampToDateTime(data['updatedAt']) ??
          _timestampToDateTime(data['createdAt']);

      transactions.add(
        UserTransaction(
          offerId: offerDoc.id,
          listingId: listing.id,
          title: listing.title,
          category: listing.category,
          listingType: listing.type,
          role: role,
          counterpartyId: counterpartyId,
          acceptedAt: acceptedAt,
        ),
      );
    }

    transactions.sort((a, b) {
      final bTime = b.acceptedAt?.millisecondsSinceEpoch ?? 0;
      final aTime = a.acceptedAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });

    return transactions;
  }

  Future<void> _ensureUrgentAllowed({
    required String ownerId,
    required ListingType type,
    required Duration? urgentDuration,
  }) async {
    final wantsUrgentBorrow = type == ListingType.borrow && urgentDuration != null;
    if (!wantsUrgentBorrow) {
      return;
    }

    final userSnapshot = await _usersRef.doc(ownerId).get();
    final userData = userSnapshot.data();
    final onboarding = userData?['onboarding'] as Map<String, dynamic>?;
    final urgentAlertsEnabled = onboarding?['urgentAlertsEnabled'] as bool? ?? false;

    if (!urgentAlertsEnabled) {
      throw StateError(
        'Enable urgent alerts in Settings to post urgent borrow requests.',
      );
    }
  }

  Future<void> _writeNotification({
    required String recipientId,
    required String actorId,
    required String type,
    required String title,
    required String body,
    String? listingId,
    String? offerId,
  }) async {
    if (recipientId.trim().isEmpty || actorId.trim().isEmpty) {
      return;
    }
    if (recipientId == actorId) {
      return;
    }

    try {
      await _notificationsRef.add({
        'recipientId': recipientId,
        'actorId': actorId,
        'type': type,
        'title': title,
        'body': body,
        'listingId': listingId,
        'offerId': offerId,
        'createdAt': FieldValue.serverTimestamp(),
        'readAt': null,
      });
    } catch (_) {
      // Notification failures should not break core offer/listing actions.
    }
  }

  Future<void> _upsertContactUnlock({
    required String ownerId,
    required String requesterId,
    required String listingId,
    required String offerId,
  }) async {
    if (ownerId.trim().isEmpty || requesterId.trim().isEmpty) {
      return;
    }

    final pairId = contactPairDocumentId(ownerId, requesterId);
    final unlockRef = _contactUnlocksRef.doc(pairId);
    final userA = ownerId.compareTo(requesterId) <= 0 ? ownerId : requesterId;
    final userB = ownerId.compareTo(requesterId) <= 0 ? requesterId : ownerId;

    try {
      await unlockRef.set({
        'userA': userA,
        'userB': userB,
        'ownerId': ownerId,
        'requesterId': requesterId,
        'listingId': listingId,
        'offerId': offerId,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Contact unlock write is best-effort here so offer acceptance still
      // succeeds even if this write is blocked by stale rules.
    }
  }

  String _deriveRequesterIdFromOfferId({
    required String listingId,
    required String offerId,
  }) {
    final prefix = '${listingId}_';
    if (!offerId.startsWith(prefix) || offerId.length <= prefix.length) {
      return '';
    }
    return offerId.substring(prefix.length);
  }
}

class _MakeOfferTransactionResult {
  const _MakeOfferTransactionResult({
    required this.result,
    this.ownerId,
    this.listingTitle,
  });

  final MakeOfferResult result;
  final String? ownerId;
  final String? listingTitle;
}
