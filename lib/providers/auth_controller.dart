import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../services/user_service.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthService authService,
    required UserService userService,
    required PushNotificationService pushNotificationService,
  })
      : _authService = authService,
        _userService = userService,
        _pushNotificationService = pushNotificationService {
    _authSub = _authService.authStateChanges().listen(_handleAuthStateChange);
  }

  final AuthService _authService;
  final UserService _userService;
  final PushNotificationService _pushNotificationService;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppUser?>? _profileSub;
  Timer? _profileLoadTimeout;

  User? _firebaseUser;
  AppUser? _profile;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _errorMessage;
  String? _lastPushSyncUid;
  bool? _lastPushSyncNotificationsEnabled;
  int _pushSyncRetryCount = 0;
  bool _hasReceivedInitialProfile = false;

  bool get isLoading => _isLoading;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  User? get firebaseUser => _firebaseUser;
  AppUser? get profile => _profile;

  bool get isSignedIn => _firebaseUser != null;

  String get email => _firebaseUser?.email ?? '';

  bool get hasColumbiaEmail =>
      email.trim().toLowerCase().endsWith('@columbia.edu');

  bool get isEmailVerified => _firebaseUser?.emailVerified ?? false;
  bool get isOnboardingComplete => _profile?.onboardingCompleted ?? false;

  bool get isVerifiedForMarketplace =>
      isSignedIn && hasColumbiaEmail && isEmailVerified;

  Future<void> _handleAuthStateChange(User? user) async {
    _firebaseUser = user;
    _errorMessage = null;

    await _profileSub?.cancel();
    _profileLoadTimeout?.cancel();
    _profileLoadTimeout = null;
    _hasReceivedInitialProfile = false;

    if (user == null) {
      _profile = null;
      _lastPushSyncUid = null;
      _lastPushSyncNotificationsEnabled = null;
      _pushSyncRetryCount = 0;
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    final normalizedEmail = (user.email ?? '').trim().toLowerCase();
    if (!normalizedEmail.endsWith('@columbia.edu')) {
      _profile = null;
      _errorMessage = 'Only @columbia.edu accounts can access Knocknock.';
      await _authService.signOut();
      _isLoading = false;
      notifyListeners();
      return;
    }

    _profileSub = _userService.watchUser(user.uid).listen((profile) {
      _profile = profile;
      if (!_hasReceivedInitialProfile) {
        _hasReceivedInitialProfile = true;
        _isLoading = false;
      }
      final notificationsEnabled = profile?.notificationsEnabled ?? false;
      final shouldSyncPush =
          _lastPushSyncUid != user.uid ||
          _lastPushSyncNotificationsEnabled != notificationsEnabled;
      if (shouldSyncPush) {
        _lastPushSyncUid = user.uid;
        _lastPushSyncNotificationsEnabled = notificationsEnabled;
        unawaited(
          _syncPushRegistration(
            uid: user.uid,
            notificationsEnabled: notificationsEnabled,
          ),
        );
      }
      notifyListeners();
    }, onError: (_) {
      if (!_hasReceivedInitialProfile) {
        _hasReceivedInitialProfile = true;
        _isLoading = false;
        notifyListeners();
      }
    });

    _profileLoadTimeout = Timer(const Duration(seconds: 3), () {
      if (!_hasReceivedInitialProfile) {
        _hasReceivedInitialProfile = true;
        _isLoading = false;
        notifyListeners();
      }
    });

    // Do non-critical bootstrap work in background so login routing is instant.
    unawaited(_bootstrapUserRecords(user));
  }

  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    int? yearInCollege,
  }) async {
    return _runAction(() async {
      await _authService.signUpWithEmail(email: email, password: password);
      final createdUser = _authService.currentUser;
      if (createdUser != null) {
        await createdUser.updateDisplayName('$firstName $lastName');
        await createdUser.reload();
        final refreshedUser = _authService.currentUser ?? createdUser;
        _firebaseUser = refreshedUser;
        await _userService.upsertUserFromAuth(
          refreshedUser,
          yearInCollege: yearInCollege,
          firstName: firstName,
          lastName: lastName,
        );
      }
    });
  }

  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _runAction(
      () => _authService.signInWithEmail(email: email, password: password),
    );
  }

  Future<bool> signInWithGoogle() {
    return _runAction(_authService.signInWithGoogle);
  }

  Future<bool> resendVerificationEmail() {
    return _runAction(_authService.resendEmailVerification);
  }

  Future<bool> refreshVerificationStatus() {
    return _runAction(() async {
      await _authService.reloadCurrentUser();
      _firebaseUser = _authService.currentUser;
      if (_firebaseUser?.emailVerified == true) {
        await _userService.markEmailVerified(_firebaseUser!.uid);
      }
      notifyListeners();
    });
  }

  Future<bool> signOut() {
    return _runAction(() async {
      final uid = _firebaseUser?.uid;
      await _authService.signOut();
      if (uid != null) {
        unawaited(_cleanupPushAfterSignOut(uid));
      }
      _lastPushSyncUid = null;
      _lastPushSyncNotificationsEnabled = null;
      _pushSyncRetryCount = 0;
      _profileLoadTimeout?.cancel();
      _profileLoadTimeout = null;
      _hasReceivedInitialProfile = false;
    });
  }

  Future<bool> _runAction(Future<void> Function() action) async {
    _errorMessage = null;
    _isBusy = true;
    notifyListeners();

    try {
      await action();
      return true;
    } on AuthFailure catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (error) {
      _errorMessage = 'Unexpected error: $error';
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    _profileLoadTimeout?.cancel();
    super.dispose();
  }

  Future<void> _syncPushRegistration({
    required String uid,
    required bool notificationsEnabled,
  }) async {
    try {
      await _pushNotificationService.syncForUser(
        userId: uid,
        notificationsEnabled: notificationsEnabled,
      );
      if (!notificationsEnabled || _pushNotificationService.hasActiveToken) {
        _pushSyncRetryCount = 0;
        return;
      }
      if (_pushSyncRetryCount >= 3) {
        return;
      }
      _pushSyncRetryCount += 1;
      unawaited(
        Future<void>.delayed(const Duration(seconds: 2), () async {
          if (_firebaseUser?.uid != uid) {
            return;
          }
          final latestEnabled = _profile?.notificationsEnabled ?? false;
          if (!latestEnabled) {
            return;
          }
          await _syncPushRegistration(
            uid: uid,
            notificationsEnabled: latestEnabled,
          );
        }),
      );
    } catch (_) {
      _lastPushSyncUid = null;
      _lastPushSyncNotificationsEnabled = null;
      _pushSyncRetryCount = 0;
      // Push registration should not block auth/profile flow.
    }
  }

  Future<void> _cleanupPushAfterSignOut(String uid) async {
    try {
      await _pushNotificationService.unregisterCurrentUser(uid);
    } catch (_) {
      // Non-blocking best-effort cleanup.
    }
  }

  Future<void> _bootstrapUserRecords(User user) async {
    try {
      await _userService.upsertUserFromAuth(user);
      if (user.emailVerified) {
        await _userService.markEmailVerified(user.uid);
      }
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }
}
