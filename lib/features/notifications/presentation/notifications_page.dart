import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_notification.dart';
import '../../../providers/auth_controller.dart';
import '../../../services/notification_service.dart';

enum NotificationsPageDestination {
  home,
  listings,
  offers,
}

class NotificationsPageIntent {
  const NotificationsPageIntent({
    required this.destination,
    this.listingId,
  });

  final NotificationsPageDestination destination;
  final String? listingId;
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthController>().firebaseUser?.uid;
    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in again.')),
      );
    }

    final notificationService = context.read<NotificationService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () => notificationService.markAllRead(userId),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: notificationService.watchMyNotifications(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data ?? const <AppNotification>[];
          if (items.isEmpty) {
            return const Center(child: Text('No notifications yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final item = items[index];
              return _NotificationRow(item: item);
            },
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemCount: items.length,
          );
        },
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    final notificationService = context.read<NotificationService>();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        if (item.isUnread) {
          await notificationService.markRead(notificationId: item.id);
        }
        if (!context.mounted) {
          return;
        }

        switch (item.type) {
          case AppNotificationType.offerReceived:
            Navigator.of(context).pop(
              NotificationsPageIntent(
                destination: NotificationsPageDestination.listings,
                listingId: item.listingId?.trim().isEmpty == true
                    ? null
                    : item.listingId?.trim(),
              ),
            );
          case AppNotificationType.offerAccepted:
          case AppNotificationType.offerDeclined:
          case AppNotificationType.returnDueSoonLender:
          case AppNotificationType.returnDueSoonBorrower:
            Navigator.of(context).pop(
              const NotificationsPageIntent(
                destination: NotificationsPageDestination.offers,
              ),
            );
          case AppNotificationType.urgentBorrowPosted:
            Navigator.of(context).pop(
              NotificationsPageIntent(
                destination: NotificationsPageDestination.home,
                listingId: item.listingId?.trim().isEmpty == true
                    ? null
                    : item.listingId?.trim(),
              ),
            );
          case AppNotificationType.urgentNoResponse:
            Navigator.of(context).pop(
              NotificationsPageIntent(
                destination: NotificationsPageDestination.listings,
                listingId: item.listingId?.trim().isEmpty == true
                    ? null
                    : item.listingId?.trim(),
              ),
            );
        }
      },
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: item.isUnread
              ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.25)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_iconForType(item.type)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(item.body),
                  const SizedBox(height: 4),
                  Text(
                    _timeText(item.createdAt),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            if (item.isUnread)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.offerReceived:
        return Icons.local_offer_outlined;
      case AppNotificationType.offerAccepted:
        return Icons.check_circle_outline;
      case AppNotificationType.offerDeclined:
        return Icons.highlight_off_outlined;
      case AppNotificationType.urgentBorrowPosted:
        return Icons.notification_important_outlined;
      case AppNotificationType.urgentNoResponse:
        return Icons.timer_off_outlined;
      case AppNotificationType.returnDueSoonLender:
      case AppNotificationType.returnDueSoonBorrower:
        return Icons.event_repeat_outlined;
    }
  }

  String _timeText(DateTime? dateTime) {
    if (dateTime == null) {
      return 'Just now';
    }
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) {
      return 'Just now';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    final weeks = (diff.inDays / 7).floor();
    return '${weeks}w ago';
  }
}
