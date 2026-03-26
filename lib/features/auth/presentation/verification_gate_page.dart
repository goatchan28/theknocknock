import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_controller.dart';

class VerificationGatePage extends StatelessWidget {
  const VerificationGatePage({super.key});

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

  Future<void> _refreshEmail(BuildContext context, AuthController auth) async {
    if (auth.isBusy) {
      return;
    }

    final success = await auth.refreshVerificationStatus();
    if (!context.mounted) {
      return;
    }

    if (!success && auth.errorMessage != null) {
      _showMessage(context, auth.errorMessage!);
      return;
    }

    if (auth.isEmailVerified) {
      _showMessage(context, 'Email verified.');
    }
  }

  Future<void> _resendEmail(BuildContext context, AuthController auth) async {
    if (auth.isBusy) {
      return;
    }

    final success = await auth.resendVerificationEmail();
    if (!context.mounted) {
      return;
    }

    if (!success && auth.errorMessage != null) {
      _showMessage(context, auth.errorMessage!);
      return;
    }

    _showMessage(context, 'Verification email resent.');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Verification')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Complete verification to use Knocknock.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text('Signed in as: ${auth.email}'),
              const SizedBox(height: 16),
              _StatusRow(
                title: 'Columbia domain',
                isComplete: auth.hasColumbiaEmail,
                doneLabel: 'Eligible',
                todoLabel: 'Must end with @columbia.edu',
              ),
              const SizedBox(height: 8),
              _StatusRow(
                title: 'Email verified',
                isComplete: auth.isEmailVerified,
                doneLabel: 'Verified',
                todoLabel: 'Verify from your inbox',
              ),
              const SizedBox(height: 24),
              if (!auth.hasColumbiaEmail)
                Text(
                  'This account is not a Columbia email. Sign out and use a '
                  '@columbia.edu account.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: auth.isBusy
                    ? null
                    : () => _refreshEmail(context, auth),
                child: auth.isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('I verified email, refresh status'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: auth.isBusy || !auth.hasColumbiaEmail
                    ? null
                    : () => _resendEmail(context, auth),
                child: const Text('Resend verification email'),
              ),
              const Spacer(),
              TextButton(
                onPressed: auth.isBusy ? null : auth.signOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.title,
    required this.isComplete,
    required this.doneLabel,
    required this.todoLabel,
  });

  final String title;
  final bool isComplete;
  final String doneLabel;
  final String todoLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isComplete ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isComplete
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Text(isComplete ? doneLabel : todoLabel),
        ],
      ),
    );
  }
}
