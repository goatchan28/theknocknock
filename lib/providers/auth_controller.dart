import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';

class AuthController extends ChangeNotifier {
  AuthController({required AuthService authService, required UserService userService})
      : _authService = authService,
        _userService = userService {
    _authSub = _authService.authStateChanges().listen(_handleAuthStateChange);
  }

  final AuthService _authService;
  final UserService _userService;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppUser?>? _profileSub;

  User? _firebaseUser;
  AppUser? _profile;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _errorMessage;

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

    if (user == null) {
      _profile = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    final normalizedEmail = (user.email ?? '').trim().toLowerCase();
    if (!normalizedEmail.endsWith('@columbia.edu')) {
      _profile = null;
      _errorMessage = 'Only @columbia.edu accounts can access Knocknock.';
      await _authService.signOut();
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      await _userService.upsertUserFromAuth(user);
      _profileSub = _userService.watchUser(user.uid).listen((profile) {
        _profile = profile;
        notifyListeners();
      });
    } catch (error) {
      _errorMessage = error.toString();
    }

    if (user.emailVerified) {
      await _userService.markEmailVerified(user.uid);
    }

    _isLoading = false;
    notifyListeners();
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
    return _runAction(() async {
      await _authService.signInWithGoogle();
      final user = _authService.currentUser;
      if (user != null) {
        await _userService.upsertUserFromAuth(user);
      }
    });
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

  Future<bool> signOut() => _runAction(_authService.signOut);

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
    super.dispose();
  }
}
