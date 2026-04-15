import 'package:cloud_firestore/cloud_firestore.dart';

import 'listing.dart';

enum OfferStatus { pending, accepted, declined }

class ListingOffer {
  const ListingOffer({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.ownerId,
    required this.requesterId,
    required this.listingType,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    required this.hasListingTypeSnapshot,
    this.pickedUpAt,
    this.returnDueAt,
    this.returnedAt,
  });

  final String id;
  final String listingId;
  final String listingTitle;
  final String ownerId;
  final String requesterId;
  final ListingType listingType;
  final OfferStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool hasListingTypeSnapshot;
  final DateTime? pickedUpAt;
  final DateTime? returnDueAt;
  final DateTime? returnedAt;

  bool get isPending => status == OfferStatus.pending;

  static OfferStatus _statusFromString(String raw) {
    switch (raw) {
      case 'accepted':
        return OfferStatus.accepted;
      case 'declined':
        return OfferStatus.declined;
      case 'pending':
        return OfferStatus.pending;
      default:
        // Legacy/unknown statuses are treated as inactive.
        return OfferStatus.declined;
    }
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }

  static ListingType _listingTypeFromString(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'borrow' || normalized.endsWith('.borrow')) {
      return ListingType.borrow;
    }
    return ListingType.lend;
  }

  factory ListingOffer.fromFirestore(String id, Map<String, dynamic> data) {
    final listingTypeRaw = (data['listingType'] as String?) ?? '';
    return ListingOffer(
      id: id,
      listingId: (data['listingId'] as String?) ?? '',
      listingTitle:
          ((data['listingTitle'] as String?) ?? (data['listingTitleSnapshot'] as String?) ?? '')
              .trim(),
      ownerId: (data['ownerId'] as String?) ?? '',
      requesterId: (data['requesterId'] as String?) ?? '',
      listingType: _listingTypeFromString(listingTypeRaw),
      status: _statusFromString((data['status'] as String?) ?? 'pending'),
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
      hasListingTypeSnapshot: listingTypeRaw.trim().isNotEmpty,
      pickedUpAt: _toDateTime(data['pickedUpAt']),
      returnDueAt: _toDateTime(data['returnDueAt']),
      returnedAt: _toDateTime(data['returnedAt']),
    );
  }

  ListingOffer copyWith({
    String? listingTitle,
    ListingType? listingType,
    bool? hasListingTypeSnapshot,
  }) {
    return ListingOffer(
      id: id,
      listingId: listingId,
      listingTitle: listingTitle ?? this.listingTitle,
      ownerId: ownerId,
      requesterId: requesterId,
      listingType: listingType ?? this.listingType,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      hasListingTypeSnapshot:
          hasListingTypeSnapshot ?? this.hasListingTypeSnapshot,
      pickedUpAt: pickedUpAt,
      returnDueAt: returnDueAt,
      returnedAt: returnedAt,
    );
  }
}
