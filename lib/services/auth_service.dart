import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  bool isColumbiaEmail(String email) {
    return email.trim().toLowerCase().endsWith('@columbia.edu');
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    if (!isColumbiaEmail(normalizedEmail)) {
      throw const AuthFailure('Use a Columbia email (@columbia.edu).');
    }

    try {
      await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      await currentUser?.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(error.message ?? 'Could not create account.');
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    try {
      await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(error.message ?? 'Could not sign in.');
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthFailure('Google sign-in cancelled.');
      }

      final googleEmail = googleUser.email.toLowerCase();
      if (!isColumbiaEmail(googleEmail)) {
        await _googleSignIn.signOut();
        throw const AuthFailure(
          'Only @columbia.edu Google accounts can use Knocknock.',
        );
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final result = await _auth.signInWithCredential(credential);
      final signedInEmail = result.user?.email?.toLowerCase() ?? '';

      if (!isColumbiaEmail(signedInEmail)) {
        await signOut();
        throw const AuthFailure(
          'Only @columbia.edu Google accounts can use Knocknock.',
        );
      }
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(error.message ?? 'Google sign-in failed.');
    }
  }

  Future<void> resendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFailure('No user signed in.');
    }
    await user.sendEmailVerification();
  }

  Future<void> reloadCurrentUser() async {
    await _auth.currentUser?.reload();
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Keep going so Firebase session is always cleared.
    }
    await _auth.signOut();
  }
}
