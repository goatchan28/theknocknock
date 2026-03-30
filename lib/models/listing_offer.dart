import 'package:cloud_firestore/cloud_firestore.dart';

enum OfferStatus { pending, accepted, declined }

class ListingOffer {
  const ListingOffer({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.ownerId,
    required this.requesterId,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String listingId;
  final String listingTitle;
  final String ownerId;
  final String requesterId;
  final OfferStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

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

  factory ListingOffer.fromFirestore(String id, Map<String, dynamic> data) {
    return ListingOffer(
      id: id,
      listingId: (data['listingId'] as String?) ?? '',
      listingTitle:
          ((data['listingTitle'] as String?) ?? (data['listingTitleSnapshot'] as String?) ?? '')
              .trim(),
      ownerId: (data['ownerId'] as String?) ?? '',
      requesterId: (data['requesterId'] as String?) ?? '',
      status: _statusFromString((data['status'] as String?) ?? 'pending'),
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
    );
  }

  ListingOffer copyWith({
    String? listingTitle,
  }) {
    return ListingOffer(
      id: id,
      listingId: listingId,
      listingTitle: listingTitle ?? this.listingTitle,
      ownerId: ownerId,
      requesterId: requesterId,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
