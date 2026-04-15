import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';

class NotificationService {
  NotificationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _notificationsRef =>
      _firestore.collection('notifications');

  Stream<List<AppNotification>> watchMyNotifications(String userId) {
    return _notificationsRef
        .where('recipientId', isEqualTo: userId)
        .limit(200)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map((doc) => AppNotification.fromFirestore(doc.id, doc.data()))
          .toList();
      items.sort((a, b) {
        final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
        final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });
      return items;
    });
  }

  Stream<int> watchUnreadCount(String userId) {
    return watchMyNotifications(userId).map(
      (items) => items.where((item) => item.isUnread).length,
    );
  }

  Future<void> markUnreadByTypes({
    required String userId,
    required Set<AppNotificationType> types,
  }) async {
    if (types.isEmpty) {
      return;
    }

    final snapshot = await _notificationsRef
        .where('recipientId', isEqualTo: userId)
        .where('readAt', isNull: true)
        .limit(200)
        .get();

    if (snapshot.docs.isEmpty) {
      return;
    }

    final batch = _firestore.batch();
    var hasUpdates = false;
    for (final doc in snapshot.docs) {
      final rawType = (doc.data()['type'] as String?)?.trim() ?? '';
      final type = _fromRawType(rawType);
      if (type == null || !types.contains(type)) {
        continue;
      }
      batch.update(doc.reference, {
        'readAt': FieldValue.serverTimestamp(),
      });
      hasUpdates = true;
    }
    if (!hasUpdates) {
      return;
    }
    await batch.commit();
  }

  AppNotificationType? _fromRawType(String raw) {
    switch (raw) {
      case 'offer_received':
        return AppNotificationType.offerReceived;
      case 'offer_accepted':
        return AppNotificationType.offerAccepted;
      case 'offer_declined':
        return AppNotificationType.offerDeclined;
      case 'urgent_borrow_posted':
        return AppNotificationType.urgentBorrowPosted;
      case 'urgent_no_response':
        return AppNotificationType.urgentNoResponse;
      case 'return_due_soon_lender':
        return AppNotificationType.returnDueSoonLender;
      case 'return_due_soon_borrower':
        return AppNotificationType.returnDueSoonBorrower;
      default:
        return null;
    }
  }

  Future<void> markRead({
    required String notificationId,
  }) async {
    await _notificationsRef.doc(notificationId).update({
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAllRead(String userId) async {
    final snapshot = await _notificationsRef
        .where('recipientId', isEqualTo: userId)
        .limit(200)
        .get();

    if (snapshot.docs.isEmpty) {
      return;
    }

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['readAt'] != null) {
        continue;
      }
      batch.update(doc.reference, {
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
