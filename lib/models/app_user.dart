import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.createdAt,
    required this.emailVerified,
    required this.columbiaEligible,
    required this.phoneVerified,
    required this.onboardingCompleted,
    required this.notificationsEnabled,
    required this.urgentAlertsEnabled,
    required this.interests,
    this.yearInCollege,
    this.firstName,
    this.lastName,
    this.displayName,
    this.photoUrl,
    this.phoneNumber,
  });

  final String uid;
  final String email;
  final DateTime? createdAt;
  final bool emailVerified;
  final bool columbiaEligible;
  final bool phoneVerified;
  final bool onboardingCompleted;
  final bool notificationsEnabled;
  final bool urgentAlertsEnabled;
  final List<String> interests;
  final int? yearInCollege;
  final String? firstName;
  final String? lastName;
  final String? displayName;
  final String? photoUrl;
  final String? phoneNumber;

  factory AppUser.fromFirestore(
    String uid,
    Map<String, dynamic> data,
  ) {
    final createdAtTimestamp = data['createdAt'];
    final verification = data['verification'] as Map<String, dynamic>?;
    final onboarding = data['onboarding'] as Map<String, dynamic>?;
    return AppUser(
      uid: uid,
      email: (data['email'] as String?) ?? '',
      createdAt: createdAtTimestamp is Timestamp
          ? createdAtTimestamp.toDate()
          : null,
      emailVerified: verification?['emailVerified'] as bool? ?? false,
      columbiaEligible: verification?['columbiaEligible'] as bool? ?? false,
      phoneVerified: verification?['phoneVerified'] as bool? ?? false,
      onboardingCompleted: onboarding?['completed'] as bool? ?? false,
      notificationsEnabled: onboarding?['notificationsEnabled'] as bool? ?? false,
      urgentAlertsEnabled: onboarding?['urgentAlertsEnabled'] as bool? ?? false,
      interests: ((onboarding?['interests'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<String>()
          .toList(),
      yearInCollege: data['yearInCollege'] as int?,
      firstName: data['firstName'] as String?,
      lastName: data['lastName'] as String?,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
      phoneNumber: data['phoneNumber'] as String?,
    );
  }
}
