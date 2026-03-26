import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class OnboardingService {
  OnboardingService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  Future<String> uploadProfilePhoto({
    required String uid,
    required XFile image,
  }) async {
    final file = File(image.path);
    final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child('users/$uid/profile/$fileName');

    final uploadTask = await ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    return uploadTask.ref.getDownloadURL();
  }
}
