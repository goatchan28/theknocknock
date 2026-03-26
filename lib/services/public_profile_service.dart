import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/public_profile.dart';

class PublicProfileService {
  PublicProfileService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<PublicProfile?> watchPublicProfile(String uid) {
    return _firestore.collection('public_profiles').doc(uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return PublicProfile.fromFirestore(doc.id, doc.data()!);
    });
  }
}
