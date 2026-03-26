import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase/firebase_initializer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrapResult = await FirebaseInitializer.initialize();
  runApp(KnocknockApp(bootstrapResult: bootstrapResult));
}
