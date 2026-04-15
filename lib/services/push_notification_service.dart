import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum PushOpenDestination {
  home,
  listings,
  offers,
}

class PushOpenIntent {
  const PushOpenIntent({
    required this.destination,
    this.type,
    this.listingId,
    this.offerId,
  });

  final PushOpenDestination destination;
  final String? type;
  final String? listingId;
  final String? offerId;
}

class PushNotificationService {
  PushNotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance {
    _openMessageSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
    unawaited(_consumeInitialMessage());
  }

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  static const MethodChannel _badgeChannel = MethodChannel('knocknock/app_badge');

  StreamSubscription<String>? _tokenRefreshSub;
  String? _activeUserId;
  String? _activeToken;
  bool? _lastNotificationsEnabled;
  Future<void>? _inFlightSync;
  StreamSubscription<RemoteMessage>? _openMessageSub;
  final _openIntentController = StreamController<PushOpenIntent>.broadcast();
  PushOpenIntent? _pendingOpenIntent;
  String? _lastHandledMessageId;

  bool get hasActiveToken =>
      _activeToken != null && _activeToken!.trim().isNotEmpty;
  Stream<PushOpenIntent> get openIntentStream => _openIntentController.stream;

  Future<void> syncForUser({
    required String userId,
    required bool notificationsEnabled,
  }) async {
    if (_inFlightSync != null) {
      await _inFlightSync;
    }

    final future = _syncInternal(
      userId: userId,
      notificationsEnabled: notificationsEnabled,
    );
    _inFlightSync = future;
    try {
      await future;
    } finally {
      if (identical(_inFlightSync, future)) {
        _inFlightSync = null;
      }
    }
  }

  Future<void> _syncInternal({
    required String userId,
    required bool notificationsEnabled,
  }) async {
    final noStateChange =
        _activeUserId == userId &&
        _lastNotificationsEnabled == notificationsEnabled &&
        (!notificationsEnabled || hasActiveToken);
    if (noStateChange) {
      return;
    }

    final previousUserId = _activeUserId;
    final previousEnabled = _lastNotificationsEnabled;
    _activeUserId = userId;
    _lastNotificationsEnabled = notificationsEnabled;
    try {
      await _messaging.setAutoInitEnabled(notificationsEnabled);
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: notificationsEnabled,
        badge: notificationsEnabled,
        sound: notificationsEnabled,
      );

      if (!notificationsEnabled) {
        await _removeCurrentTokenFromUser(userId);
        await _clearAllTokensFromUser(userId);
        await _messaging.deleteToken();
        await setAppIconBadgeCount(0);
        _activeToken = null;
        await _tokenRefreshSub?.cancel();
        _tokenRefreshSub = null;
        return;
      }

      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final status = settings.authorizationStatus;
      final canNotify = status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional;

      if (!canNotify) {
        await _removeCurrentTokenFromUser(userId);
        _activeToken = null;
        return;
      }

      final token = await _getTokenWithRetry();
      if (token != null && token.trim().isNotEmpty) {
        _activeToken = token;
        await _upsertToken(userId, token);
      } else {
        _activeToken = null;
      }

      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((refreshedToken) async {
        final uid = _activeUserId;
        if (uid == null || refreshedToken.trim().isEmpty) {
          return;
        }
        _activeToken = refreshedToken;
        await _upsertToken(uid, refreshedToken);
      });
    } catch (_) {
      _activeUserId = previousUserId;
      _lastNotificationsEnabled = previousEnabled;
      rethrow;
    }
  }

  Future<void> unregisterCurrentUser(String userId) async {
    await _removeCurrentTokenFromUser(userId);
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _activeUserId = null;
    _activeToken = null;
    _lastNotificationsEnabled = null;
    await setAppIconBadgeCount(0);
  }

  Future<void> setAppIconBadgeCount(int count) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    final safeCount = count < 0 ? 0 : count;
    try {
      await _badgeChannel.invokeMethod('setBadgeCount', safeCount);
    } catch (_) {
      // Non-fatal; app should continue even if badge API is unavailable.
    }
  }

  Future<void> _upsertToken(String userId, String token) async {
    await _firestore.collection('users').doc(userId).update({
      'notificationTokens': FieldValue.arrayUnion([token]),
    });
  }

  Future<void> _removeCurrentTokenFromUser(String userId) async {
    final token = _activeToken ?? await _messaging.getToken();
    if (token == null || token.trim().isEmpty) {
      return;
    }
    try {
      await _firestore.collection('users').doc(userId).update({
        'notificationTokens': FieldValue.arrayRemove([token]),
      });
    } catch (_) {
      // Non-fatal for logout or denied notification permission flows.
    }
  }

  Future<void> _clearAllTokensFromUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'notificationTokens': <String>[],
      });
    } catch (_) {
      // Non-fatal for clients with restrictive rules.
    }
  }

  PushOpenIntent? takePendingOpenIntent() {
    final pending = _pendingOpenIntent;
    _pendingOpenIntent = null;
    return pending;
  }

  Future<void> _consumeInitialMessage() async {
    try {
      final message = await _messaging.getInitialMessage();
      if (message != null) {
        _handleOpenedMessage(message);
      }
    } catch (_) {
      // Non-fatal for app startup.
    }
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final messageId = message.messageId;
    if (messageId != null && messageId == _lastHandledMessageId) {
      return;
    }
    _lastHandledMessageId = messageId;

    final intent = _intentFromMessageData(message.data);
    if (intent == null) {
      return;
    }

    _pendingOpenIntent = intent;
    if (!_openIntentController.isClosed) {
      _openIntentController.add(intent);
    }
  }

  PushOpenIntent? _intentFromMessageData(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().trim();
    if (type.isEmpty) {
      return null;
    }

    final listingId = (data['listingId'] ?? '').toString().trim();
    final offerId = (data['offerId'] ?? '').toString().trim();

    switch (type) {
      case 'offer_received':
        return PushOpenIntent(
          destination: PushOpenDestination.listings,
          type: type,
          listingId: listingId.isEmpty ? null : listingId,
          offerId: offerId.isEmpty ? null : offerId,
        );
      case 'offer_accepted':
      case 'offer_declined':
      case 'return_due_soon_lender':
      case 'return_due_soon_borrower':
        return PushOpenIntent(
          destination: PushOpenDestination.offers,
          type: type,
          listingId: listingId.isEmpty ? null : listingId,
          offerId: offerId.isEmpty ? null : offerId,
        );
      case 'urgent_borrow_posted':
        return PushOpenIntent(
          destination: PushOpenDestination.home,
          type: type,
          listingId: listingId.isEmpty ? null : listingId,
          offerId: offerId.isEmpty ? null : offerId,
        );
      case 'urgent_no_response':
        return PushOpenIntent(
          destination: PushOpenDestination.listings,
          type: type,
          listingId: listingId.isEmpty ? null : listingId,
          offerId: offerId.isEmpty ? null : offerId,
        );
      default:
        return PushOpenIntent(
          destination: PushOpenDestination.home,
          type: type,
          listingId: listingId.isEmpty ? null : listingId,
          offerId: offerId.isEmpty ? null : offerId,
        );
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _openMessageSub?.cancel();
    _openIntentController.close();
  }

  Future<String?> _getTokenWithRetry() async {
    const maxAttempts = 5;
    for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken == null || apnsToken.trim().isEmpty) {
          if (attempt < maxAttempts - 1) {
            await Future<void>.delayed(const Duration(seconds: 1));
            continue;
          }
        }
      }

      final token = await _messaging.getToken();
      if (token != null && token.trim().isNotEmpty) {
        return token;
      }
      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    return null;
  }
}
