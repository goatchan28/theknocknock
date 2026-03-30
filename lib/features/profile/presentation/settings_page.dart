import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/input_formatters/us_phone_input_formatter.dart';
import '../../../providers/auth_controller.dart';
import '../../../services/user_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _phoneController = TextEditingController();
  final _phoneFocusNode = FocusNode();

  bool _notificationsEnabled = false;
  bool _urgentAlertsEnabled = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthController>().profile;
    _phoneController.text = UsPhoneInputFormatter.formatForDisplay(
      (profile?.phoneNumber ?? '').trim(),
    );
    _notificationsEnabled = profile?.notificationsEnabled ?? false;
    _urgentAlertsEnabled = profile?.urgentAlertsEnabled ?? false;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.firebaseUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Contact', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          AutofillGroup(
            child: TextField(
              controller: _phoneController,
              focusNode: _phoneFocusNode,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: const [UsPhoneInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '(212) 555-0100',
                helperText: 'Tip: tap the number suggestion above your keyboard.',
              ),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _phoneFocusNode.requestFocus(),
              icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
              label: const Text('Use iPhone autofill'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Preferences', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            value: _notificationsEnabled,
            onChanged: (value) {
              setState(() {
                _notificationsEnabled = value;
              });
            },
            title: const Text('Enable notifications'),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Text(
              'To fully disable iPhone alerts, also turn off Notifications for Knocknock in iPhone Settings.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SwitchListTile(
            value: _urgentAlertsEnabled,
            onChanged: (value) {
              setState(() {
                _urgentAlertsEnabled = value;
              });
            },
            title: const Text('Enable urgent alerts'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving || user == null ? null : () => _save(user.uid),
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save settings'),
          ),
          const SizedBox(height: 20),
          Text('About Knocknock', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: const Text(
              'Knocknock is a Columbia-only borrow/lend marketplace. '
              'Contact details are only shown after a match is accepted.',
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: auth.isBusy ? null : auth.signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  Future<void> _save(String uid) async {
    final valid = UsPhoneInputFormatter.isValid(_phoneController.text);
    if (!valid) {
      _showMessage('Enter a valid 10-digit phone number.');
      return;
    }
    final phone = UsPhoneInputFormatter.normalizeForStorage(_phoneController.text);

    setState(() {
      _saving = true;
    });

    try {
      await context.read<UserService>().updateSettings(
            uid: uid,
            phoneNumber: phone,
            notificationsEnabled: _notificationsEnabled,
            urgentAlertsEnabled: _urgentAlertsEnabled,
          );
      if (!mounted) {
        return;
      }
      _showMessage('Settings updated.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not save settings: $error');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
