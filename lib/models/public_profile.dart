import 'package:cloud_firestore/cloud_firestore.dart';

class PublicProfile {
  const PublicProfile({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
    required this.createdAt,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final DateTime? createdAt;

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }

  factory PublicProfile.fromFirestore(String uid, Map<String, dynamic> data) {
    return PublicProfile(
      uid: uid,
      displayName: ((data['displayName'] as String?) ?? 'Columbia Student').trim(),
      photoUrl: data['photoUrl'] as String?,
      createdAt: _toDateTime(data['createdAt']),
    );
  }
}
