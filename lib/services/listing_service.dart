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

  Stream<List<ListingOffer>> watchMyOffers(String requesterId) {
    return _offersRef
        .where('requesterId', isEqualTo: requesterId)
        .limit(300)
        .snapshots()
        .asyncMap((snapshot) async {
      var offers = snapshot.docs
          .map((doc) => ListingOffer.fromFirestore(doc.id, doc.data()))
          .toList();

      final missingTitleListingIds = offers
          .where(
            (offer) => offer.listingTitle.trim().isEmpty && offer.listingId.trim().isNotEmpty,
          )
          .map((offer) => offer.listingId)
          .toSet()
          .toList();

      if (missingTitleListingIds.isNotEmpty) {
        final listingSnapshots = await Future.wait(
          missingTitleListingIds.map((listingId) => _listingsRef.doc(listingId).get()),
        );

        final titleByListingId = <String, String>{};
        for (final listingSnapshot in listingSnapshots) {
          final data = listingSnapshot.data();
          if (data == null) {
            continue;
          }
          final title = (data['title'] as String?)?.trim() ?? '';
          if (title.isNotEmpty) {
            titleByListingId[listingSnapshot.id] = title;
          }
        }

        offers = offers.map((offer) {
          if (offer.listingTitle.trim().isNotEmpty) {
            return offer;
          }
          final hydratedTitle = titleByListingId[offer.listingId];
          if (hydratedTitle == null || hydratedTitle.isEmpty) {
            return offer;
          }
          return offer.copyWith(listingTitle: hydratedTitle);
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
    Duration? urgentDuration,
    XFile? image,
  }) async {
    await _ensureUrgentAllowed(
      ownerId: ownerId,
      type: type,
      urgentDuration: urgentDuration,
    );

    final docRef = _listingsRef.doc();
    String? imageUrl;

    if (image != null) {
      imageUrl = await _uploadListingImage(
        ownerId: ownerId,
        listingId: docRef.id,
        image: image,
      );
    }

    final urgentUntil = type == ListingType.borrow && urgentDuration != null
        ? Timestamp.fromDate(DateTime.now().add(urgentDuration))
        : null;

    await docRef.set({
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
      'urgentUntil': urgentUntil,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return docRef.id;
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

    final urgentUntil = type == ListingType.borrow && urgentDuration != null
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
      'urgentUntil': urgentUntil,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setListingArchived({
    required String listingId,
    required String ownerId,
    required bool archived,
  }) async {
    final listingRef = _listingsRef.doc(listingId);

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
      final acceptedOfferId = (data['acceptedOfferId'] as String?)?.trim() ?? '';
      final archivedFromSold = data['archivedFromSold'] as bool? ?? false;
      String nextStatus = currentStatus;
      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (archived) {
        if (currentStatus == 'active' || currentStatus == 'sold') {
          nextStatus = 'archived';
        }
        updateData['archivedFromSold'] = currentStatus == 'sold';
      } else {
        if (currentStatus == 'archived') {
          nextStatus =
              (acceptedOfferId.isNotEmpty || archivedFromSold) ? 'sold' : 'active';
        }
        updateData['archivedFromSold'] = FieldValue.delete();
      }

      updateData['status'] = nextStatus;
      transaction.update(listingRef, updateData);
    });
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
        'ownerId': ownerId,
        'requesterId': requesterId,
        'status': 'pending',
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
    String acceptedRequesterId = '';
    String listingTitle = '';

    await _firestore.runTransaction((transaction) async {
      final listingSnapshot = await transaction.get(listingRef);
      if (!listingSnapshot.exists || listingSnapshot.data() == null) {
        throw StateError('Listing not found.');
      }

      final listingData = listingSnapshot.data()!;
      final listingOwner = (listingData['ownerId'] as String?) ?? '';
      final listingStatus = (listingData['status'] as String?) ?? 'active';

      if (listingOwner != ownerId) {
        throw StateError('Only the owner can accept offers.');
      }

      if (listingStatus != 'active') {
        throw StateError('Listing is no longer active.');
      }

      final acceptedOfferSnapshot = await transaction.get(acceptedOfferRef);
      if (!acceptedOfferSnapshot.exists || acceptedOfferSnapshot.data() == null) {
        throw StateError('Offer no longer exists.');
      }

      final offerData = acceptedOfferSnapshot.data()!;
      if ((offerData['ownerId'] as String?) != ownerId ||
          (offerData['listingId'] as String?) != listingId) {
        throw StateError('Offer does not belong to this listing.');
      }
      final requesterId = (offerData['requesterId'] as String?) ?? '';
      if (requesterId.isEmpty) {
        throw StateError('Offer requester is missing.');
      }
      acceptedRequesterId = requesterId;
      listingTitle = (listingData['title'] as String?)?.trim() ?? '';

      final offerStatus = (offerData['status'] as String?) ?? 'pending';
      if (offerStatus != 'pending') {
        throw StateError('Only pending offers can be accepted.');
      }

      transaction.update(acceptedOfferRef, {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(listingRef, {
        'status': 'sold',
        'acceptedOfferId': offerId,
        'acceptedRequesterId': requesterId,
        'archivedFromSold': FieldValue.delete(),
        'matchedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final pairId = contactPairDocumentId(ownerId, requesterId);
      final unlockRef = _contactUnlocksRef.doc(pairId);
      final userA = ownerId.compareTo(requesterId) <= 0 ? ownerId : requesterId;
      final userB = ownerId.compareTo(requesterId) <= 0 ? requesterId : ownerId;

      transaction.set(unlockRef, {
        'userA': userA,
        'userB': userB,
        'ownerId': ownerId,
        'requesterId': requesterId,
        'listingId': listingId,
        'offerId': offerId,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

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

  Future<void> submitListingReport({
    required String listingId,
    required String reporterId,
    required String reason,
  }) async {
    await _reportsRef.add({
      'listingId': listingId,
      'reporterId': reporterId,
      'reason': reason.trim(),
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
      },
      {
        'id': 'demo_${ownerId}_borrow_calculator',
        'title': 'Need TI-84 Calculator',
        'description': 'Need one for a quiz this afternoon.',
        'category': 'School Supplies',
        'type': 'borrow',
        'status': 'active',
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
