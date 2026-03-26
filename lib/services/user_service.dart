import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';

class UserService {
  UserService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> userRef(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> publicProfileRef(String uid) {
    return _firestore.collection('public_profiles').doc(uid);
  }

  Stream<AppUser?> watchUser(String uid) {
    return userRef(uid).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }
      return AppUser.fromFirestore(snapshot.id, snapshot.data()!);
    });
  }

  Future<void> upsertUserFromAuth(
    User user, {
    int? yearInCollege,
    String? firstName,
    String? lastName,
  }) async {
    final docRef = userRef(user.uid);
    final existingDoc = await docRef.get();
    final existingData = existingDoc.data();
    final userData = <String, dynamic>{
      'email': (user.email ?? '').toLowerCase(),
      'verification': {
        'emailVerified': user.emailVerified,
        'columbiaEligible':
            (user.email ?? '').toLowerCase().endsWith('@columbia.edu'),
        'phoneVerified': user.phoneNumber != null,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };
    String? resolvedDisplayName;
    String? resolvedPhotoUrl;

    if (firstName != null && firstName.trim().isNotEmpty) {
      userData['firstName'] = firstName.trim();
    }

    if (lastName != null && lastName.trim().isNotEmpty) {
      userData['lastName'] = lastName.trim();
    }

    if (firstName != null &&
        firstName.trim().isNotEmpty &&
        lastName != null &&
        lastName.trim().isNotEmpty) {
      resolvedDisplayName = '${firstName.trim()} ${lastName.trim()}';
      userData['displayName'] = resolvedDisplayName;
    } else if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
      resolvedDisplayName = user.displayName!.trim();
      userData['displayName'] = resolvedDisplayName;
    }

    if (user.photoURL != null && user.photoURL!.trim().isNotEmpty) {
      resolvedPhotoUrl = user.photoURL!.trim();
      userData['photoUrl'] = resolvedPhotoUrl;
    }

    if (user.phoneNumber != null && user.phoneNumber!.trim().isNotEmpty) {
      userData['phoneNumber'] = user.phoneNumber;
    }

    if (yearInCollege != null) {
      userData['yearInCollege'] = yearInCollege;
    }

    if (!existingDoc.exists) {
      userData['createdAt'] = FieldValue.serverTimestamp();
      userData['onboarding'] = {
        'completed': false,
        'notificationsEnabled': false,
        'urgentAlertsEnabled': false,
        'interests': <String>[],
      };
      userData['stats'] = {
        'lentCount': 0,
        'borrowedCount': 0,
      };
    }

    await docRef.set(userData, SetOptions(merge: true));

    resolvedDisplayName ??=
        (existingData?['displayName'] as String?)?.trim();
    resolvedPhotoUrl ??= (existingData?['photoUrl'] as String?)?.trim();

    await _upsertPublicProfile(
      uid: user.uid,
      displayName: resolvedDisplayName,
      photoUrl: resolvedPhotoUrl,
      isNew: !existingDoc.exists,
    );
  }

  Future<void> markEmailVerified(String uid) async {
    await userRef(uid).update({
      'verification.emailVerified': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markPhoneVerified({
    required String uid,
    required String phoneNumber,
  }) async {
    await userRef(uid).update({
      'phoneNumber': phoneNumber,
      'verification.phoneVerified': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> savePhoneNumberForOnboarding({
    required String uid,
    required String phoneNumber,
  }) async {
    await userRef(uid).set(
      {
        'phoneNumber': phoneNumber.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> completeOnboarding({
    required String uid,
    required String phoneNumber,
    required List<String> interests,
    required bool notificationsEnabled,
    required bool urgentAlertsEnabled,
    String? photoUrl,
  }) async {
    final updateData = <String, dynamic>{
      'phoneNumber': phoneNumber.trim(),
      'onboarding': {
        'completed': true,
        'completedAt': FieldValue.serverTimestamp(),
        'notificationsEnabled': notificationsEnabled,
        'urgentAlertsEnabled': urgentAlertsEnabled,
        'interests': interests,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      updateData['photoUrl'] = photoUrl.trim();
    }

    await userRef(uid).set(updateData, SetOptions(merge: true));

    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      await publicProfileRef(uid).set(
        {
          'photoUrl': photoUrl.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

  Future<void> updateSettings({
    required String uid,
    required String phoneNumber,
    required bool notificationsEnabled,
    required bool urgentAlertsEnabled,
  }) async {
    await userRef(uid).update({
      'phoneNumber': phoneNumber.trim(),
      'onboarding.notificationsEnabled': notificationsEnabled,
      'onboarding.urgentAlertsEnabled': urgentAlertsEnabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _upsertPublicProfile({
    required String uid,
    required bool isNew,
    String? displayName,
    String? photoUrl,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (displayName != null && displayName.trim().isNotEmpty) {
      data['displayName'] = displayName.trim();
    }

    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      data['photoUrl'] = photoUrl.trim();
    }

    if (isNew) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }

    await publicProfileRef(uid).set(data, SetOptions(merge: true));
  }
}
