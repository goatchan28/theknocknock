import 'package:firebase_core/firebase_core.dart';

class FirebaseBootstrapResult {
  const FirebaseBootstrapResult._({this.app, this.error});

  final FirebaseApp? app;
  final Object? error;

  bool get isReady => app != null;

  static FirebaseBootstrapResult success(FirebaseApp app) =>
      FirebaseBootstrapResult._(app: app);

  static FirebaseBootstrapResult failure(Object error) =>
      FirebaseBootstrapResult._(error: error);
}

class FirebaseInitializer {
  static Future<FirebaseBootstrapResult> initialize() async {
    try {
      final app = await Firebase.initializeApp();
      return FirebaseBootstrapResult.success(app);
    } catch (error) {
      return FirebaseBootstrapResult.failure(error);
    }
  }
}
