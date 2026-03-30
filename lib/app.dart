import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_landing_page.dart';
import 'features/auth/presentation/firebase_setup_required_page.dart';
import 'features/auth/presentation/verification_gate_page.dart';
import 'features/onboarding/presentation/onboarding_flow_page.dart';
import 'features/shell/presentation/app_shell_page.dart';
import 'firebase/firebase_initializer.dart';
import 'providers/auth_controller.dart';
import 'services/auth_service.dart';
import 'services/listing_service.dart';
import 'services/notification_service.dart';
import 'services/onboarding_service.dart';
import 'services/push_notification_service.dart';
import 'services/public_profile_service.dart';
import 'services/user_service.dart';

class KnocknockApp extends StatelessWidget {
  const KnocknockApp({super.key, required this.bootstrapResult});

  final FirebaseBootstrapResult bootstrapResult;

  @override
  Widget build(BuildContext context) {
    if (!bootstrapResult.isReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: FirebaseSetupRequiredPage(error: bootstrapResult.error),
      );
    }

    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<UserService>(create: (_) => UserService()),
        Provider<OnboardingService>(create: (_) => OnboardingService()),
        Provider<ListingService>(create: (_) => ListingService()),
        Provider<NotificationService>(create: (_) => NotificationService()),
        Provider<PushNotificationService>(
          create: (_) => PushNotificationService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<PublicProfileService>(create: (_) => PublicProfileService()),
        ChangeNotifierProvider<AuthController>(
          create: (context) => AuthController(
            authService: context.read<AuthService>(),
            userService: context.read<UserService>(),
            pushNotificationService: context.read<PushNotificationService>(),
          ),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Knocknock',
        theme: AppTheme.lightTheme,
        home: const _RootRouter(),
      ),
    );
  }
}

class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!auth.isSignedIn) {
      return const AuthLandingPage();
    }

    if (!auth.isVerifiedForMarketplace) {
      return const VerificationGatePage();
    }

    if (!auth.isOnboardingComplete) {
      return const OnboardingFlowPage();
    }

    return const AppShellPage();
  }
}
