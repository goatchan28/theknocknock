import 'package:cloud_firestore/cloud_firestore.dart';

enum ListingType { lend, borrow }

enum ListingStatus { active, archived, sold }

class Listing {
  const Listing({
    required this.id,
    required this.ownerId,
    required this.ownerDisplayName,
    required this.ownerPhotoUrl,
    required this.title,
    required this.description,
    required this.category,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.imageUrl,
    required this.urgent,
    required this.acceptedOfferId,
    required this.acceptedRequesterId,
    required this.archivedFromSold,
    required this.returnedFromMatch,
    this.pickedUpAt,
    this.returnDueAt,
    this.urgentUntil,
  });

  final String id;
  final String ownerId;
  final String ownerDisplayName;
  final String? ownerPhotoUrl;
  final String title;
  final String description;
  final String category;
  final ListingType type;
  final ListingStatus status;
  final DateTime? createdAt;
  final DateTime? urgentUntil;
  final bool urgent;
  final String? imageUrl;
  final String? acceptedOfferId;
  final String? acceptedRequesterId;
  final bool archivedFromSold;
  final bool returnedFromMatch;
  final DateTime? pickedUpAt;
  final DateTime? returnDueAt;

  bool get isBorrow => type == ListingType.borrow;
  bool get isLend => type == ListingType.lend;
  bool get isActive => status == ListingStatus.active;
  bool get isSold => status == ListingStatus.sold;
  bool get hasAcceptedMatch =>
      acceptedOfferId != null && acceptedOfferId!.trim().isNotEmpty;

  bool get hasUrgentTimer {
    if (!isBorrow || urgentUntil == null) {
      return false;
    }
    return urgentUntil!.isAfter(DateTime.now());
  }

  bool get isUrgent {
    if (!isBorrow) {
      return false;
    }
    if (urgent) {
      return true;
    }
    return hasUrgentTimer;
  }

  static ListingType _typeFromString(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'borrow' || normalized.endsWith('.borrow')) {
      return ListingType.borrow;
    }
    if (normalized == 'lend' || normalized.endsWith('.lend')) {
      return ListingType.lend;
    }
    return ListingType.lend;
  }

  static ListingStatus _statusFromString(String raw) {
    switch (raw) {
      case 'archived':
        return ListingStatus.archived;
      case 'sold':
        return ListingStatus.sold;
      case 'active':
      default:
        return ListingStatus.active;
    }
  }

  static DateTime? _timestampToDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }

  factory Listing.fromFirestore(String id, Map<String, dynamic> data) {
    return Listing(
      id: id,
      ownerId: (data['ownerId'] as String?) ?? '',
      ownerDisplayName:
          (data['ownerDisplayName'] as String?)?.trim().isNotEmpty == true
              ? (data['ownerDisplayName'] as String).trim()
              : 'Columbia Student',
      ownerPhotoUrl: data['ownerPhotoUrl'] as String?,
      title: ((data['title'] as String?) ?? '').trim(),
      description: ((data['description'] as String?) ?? '').trim(),
      category: ((data['category'] as String?) ?? 'Other').trim(),
      type: _typeFromString((data['type'] as String?) ?? 'lend'),
      status: _statusFromString((data['status'] as String?) ?? 'active'),
      createdAt: _timestampToDateTime(data['createdAt']),
      urgentUntil: _timestampToDateTime(data['urgentUntil']),
      urgent:
          data['urgent'] as bool? ??
          (_typeFromString((data['type'] as String?) ?? 'lend') ==
                  ListingType.borrow &&
              _timestampToDateTime(data['urgentUntil']) != null),
      imageUrl: data['imageUrl'] as String?,
      acceptedOfferId: (data['acceptedOfferId'] as String?)?.trim(),
      acceptedRequesterId: (data['acceptedRequesterId'] as String?)?.trim(),
      archivedFromSold: data['archivedFromSold'] as bool? ?? false,
      returnedFromMatch:
          (data['returnedFromMatch'] as bool? ?? false) ||
          ((data['status'] as String?) == 'archived' &&
              data['returnedAt'] is Timestamp),
      pickedUpAt: _timestampToDateTime(data['pickedUpAt']),
      returnDueAt: _timestampToDateTime(data['returnDueAt']),
    );
  }
}
