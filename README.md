# Knocknock MVP

Cross-platform Flutter + Firebase MVP for a Columbia-only borrow/lend marketplace.

## Phase 1 status

Implemented:
- App shell with Material 3 theme and Provider state wiring
- Firebase bootstrap with setup guard screen when Firebase is missing
- Sign up (email/password + year in college)
- Sign in (email/password + Google sign-in)
- Columbia domain gating (`@columbia.edu`)
- Verification gate that blocks product access until email is verified
- Basic 5-tab post-auth placeholder shell for upcoming phases

## Firebase setup

1. Install FlutterFire CLI and configure this project:
   - `flutterfire configure`
2. Ensure the generated platform configuration is present.
3. Enable Firebase Authentication providers:
   - Email/Password
   - Google
4. Create Firestore in native mode.

## Run

1. `flutter pub get`
2. `flutter run`

If Firebase is not configured correctly, the app shows a setup-required screen with the initialization error.
