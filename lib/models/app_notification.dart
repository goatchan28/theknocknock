import 'package:cloud_firestore/cloud_firestore.dart';

enum AppNotificationType {
  offerReceived,
  offerAccepted,
  offerDeclined,
  urgentBorrowPosted,
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.recipientId,
    required this.actorId,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.readAt,
    this.listingId,
    this.offerId,
  });

  final String id;
  final String recipientId;
  final String actorId;
  final AppNotificationType type;
  final String title;
  final String body;
  final DateTime? createdAt;
  final DateTime? readAt;
  final String? listingId;
  final String? offerId;

  bool get isUnread => readAt == null;

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }

  static AppNotificationType _typeFromRaw(String raw) {
    switch (raw) {
      case 'offer_received':
        return AppNotificationType.offerReceived;
      case 'offer_accepted':
        return AppNotificationType.offerAccepted;
      case 'offer_declined':
        return AppNotificationType.offerDeclined;
      case 'urgent_borrow_posted':
        return AppNotificationType.urgentBorrowPosted;
      default:
        return AppNotificationType.offerReceived;
    }
  }

  factory AppNotification.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return AppNotification(
      id: id,
      recipientId: (data['recipientId'] as String?) ?? '',
      actorId: (data['actorId'] as String?) ?? '',
      type: _typeFromRaw((data['type'] as String?) ?? ''),
      title: ((data['title'] as String?) ?? 'Notification').trim(),
      body: ((data['body'] as String?) ?? '').trim(),
      listingId: (data['listingId'] as String?)?.trim(),
      offerId: (data['offerId'] as String?)?.trim(),
      createdAt: _toDateTime(data['createdAt']),
      readAt: _toDateTime(data['readAt']),
    );
  }
}
