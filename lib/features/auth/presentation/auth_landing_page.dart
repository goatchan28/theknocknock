import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_controller.dart';
import '../../../shared/widgets/knocknock_logo.dart';

class AuthLandingPage extends StatelessWidget {
  const AuthLandingPage({super.key});

  void _showMessage(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _continueWithGoogle(
    BuildContext context,
    AuthController auth,
  ) async {
    if (auth.isBusy) {
      return;
    }

    final success = await auth.signInWithGoogle();
    if (!context.mounted) {
      return;
    }

    if (!success && auth.errorMessage != null) {
      _showMessage(context, auth.errorMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(
        title: const KnocknockWordmark(width: 154, height: 36),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              const KnocknockLogo(),
              const SizedBox(height: 12),
              const KnocknockWordmark(),
              const SizedBox(height: 12),
              const Text(
                'Columbia-only borrow/lend marketplace.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                'Use your Columbia Google account to continue.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      auth.isBusy ? null : () => _continueWithGoogle(context, auth),
                  icon: const Icon(Icons.login),
                  label: auth.isBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continue with Google'),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Only @columbia.edu accounts are allowed.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
