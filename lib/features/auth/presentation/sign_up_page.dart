import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_controller.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _ClassYearOption? _selectedClassYear;
  bool _actionInFlight = false;
  String? _lastSnackMessage;
  DateTime? _lastSnackAt;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
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
      final success = await auth.signUpWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        yearInCollege: _selectedClassYear?.yearInCollege,
      );

      if (!mounted) {
        return;
      }

      if (!success && auth.errorMessage != null) {
        _showMessage(auth.errorMessage!);
        return;
      }

      _showMessage(
        'Account created. Check your email for verification.',
      );
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
              controller: _firstNameController,
              decoration: const InputDecoration(labelText: 'First name'),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Enter your first name.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastNameController,
              decoration: const InputDecoration(labelText: 'Last name'),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Enter your last name.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Columbia email'),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                final email = value?.trim().toLowerCase() ?? '';
                if (email.isEmpty) {
                  return 'Enter your email.';
                }
                if (!email.endsWith('@columbia.edu')) {
                  return 'Only @columbia.edu emails are allowed.';
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
                final password = value ?? '';
                if (password.length < 6) {
                  return 'Use at least 6 characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<_ClassYearOption>(
              value: _selectedClassYear,
              decoration: const InputDecoration(
                labelText: 'Year in college (optional)',
              ),
              hint: const Text('Select class year'),
              items: _ClassYearOption.values
                  .map(
                    (option) => DropdownMenuItem<_ClassYearOption>(
                      value: option,
                      child: Text(option.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedClassYear = value;
                });
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
                  : const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassYearOption {
  const _ClassYearOption(this.label, this.yearInCollege);

  final String label;
  final int yearInCollege;

  static const values = [
    _ClassYearOption('Freshman', 1),
    _ClassYearOption('Sophomore', 2),
    _ClassYearOption('Junior', 3),
    _ClassYearOption('Senior', 4),
  ];
}
