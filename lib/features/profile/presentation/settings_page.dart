import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_controller.dart';
import '../../../services/user_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _phoneController = TextEditingController();

  bool _notificationsEnabled = false;
  bool _urgentAlertsEnabled = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthController>().profile;
    _phoneController.text = (profile?.phoneNumber ?? '').trim();
    _notificationsEnabled = profile?.notificationsEnabled ?? false;
    _urgentAlertsEnabled = profile?.urgentAlertsEnabled ?? false;
  }

  @override
  void dispose() {
    _phoneController.dispose();
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
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '+1 212 555 0100',
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
    final phone = _phoneController.text.trim();
    final valid = RegExp(r'^\+?[0-9]{10,15}$').hasMatch(phone);
    if (!valid) {
      _showMessage('Enter a valid phone number (digits, optional +).');
      return;
    }

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
