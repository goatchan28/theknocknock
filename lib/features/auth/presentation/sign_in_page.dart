import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_controller.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _actionInFlight = false;
  String? _lastSnackMessage;
  DateTime? _lastSnackAt;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    final now = DateTime.now();
    final shouldSuppressDuplicate =
        _lastSnackMessage == message &&
        _lastSnackAt != null &&
        now.difference(_lastSnackAt!) < const Duration(seconds: 2);
    if (shouldSuppressDuplicate) {
      return;
    }
    _lastSnackMessage = message;
    _lastSnackAt = now;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final auth = context.read<AuthController>();
    if (auth.isBusy || _actionInFlight) {
      return;
    }

    setState(() {
      _actionInFlight = true;
    });

    try {
      final success = await auth.signInWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
      );

      if (!mounted) {
        return;
      }

      if (!success && auth.errorMessage != null) {
        _showMessage(auth.errorMessage!);
      }
    } finally {
      if (mounted) {
        setState(() {
          _actionInFlight = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    final auth = context.read<AuthController>();
    if (auth.isBusy || _actionInFlight) {
      return;
    }

    setState(() {
      _actionInFlight = true;
    });

    try {
      final success = await auth.signInWithGoogle();

      if (!mounted) {
        return;
      }

      if (!success && auth.errorMessage != null) {
        _showMessage(auth.errorMessage!);
      }
    } finally {
      if (mounted) {
        setState(() {
          _actionInFlight = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Columbia email'),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) {
                  return 'Enter your email.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              validator: (value) {
                if ((value ?? '').isEmpty) {
                  return 'Enter your password.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: auth.isBusy || _actionInFlight ? null : _submit,
              child: auth.isBusy || _actionInFlight
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sign In'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed:
                  auth.isBusy || _actionInFlight ? null : _signInWithGoogle,
              icon: const Icon(Icons.login),
              label: const Text('Sign In With Google'),
            ),
          ],
        ),
      ),
    );
  }
}
