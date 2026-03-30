import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/media/image_pick_and_crop.dart';
import '../../../models/user_transaction.dart';
import '../../../providers/auth_controller.dart';
import '../../../services/listing_service.dart';
import '../../../services/onboarding_service.dart';
import '../../../services/user_service.dart';
import 'settings_page.dart';
import 'transaction_history_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _imagePicker = ImagePicker();
  bool _photoUpdating = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.firebaseUser;
    final profile = auth.profile;

    if (user == null) {
      return const Center(child: Text('Please sign in again.'));
    }

    final fallbackName = (user.displayName ?? '').trim();
    final displayName = (profile?.displayName ?? '').trim().isNotEmpty
        ? profile!.displayName!.trim()
        : (fallbackName.isNotEmpty ? fallbackName : 'Columbia Student');
    final photoUrl = (profile?.photoUrl ?? user.photoURL ?? '').trim();
    final joinedAt = profile?.createdAt;

    return StreamBuilder<List<UserTransaction>>(
      stream: context.read<ListingService>().watchUserTransactions(user.uid),
      builder: (context, snapshot) {
        final transactions = snapshot.data ?? const <UserTransaction>[];
        final lentTransactions = transactions
            .where((tx) => tx.role == TransactionRole.lent)
            .toList();
        final borrowedTransactions = transactions
            .where((tx) => tx.role == TransactionRole.borrowed)
            .toList();
        final lentCount = lentTransactions.length;
        final borrowedCount = borrowedTransactions.length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: _EditableProfileAvatar(
                photoUrl: photoUrl,
                onEdit: _photoUpdating ? null : () => _changeProfilePhoto(),
                isBusy: _photoUpdating,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                displayName,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                joinedAt != null ? 'Joined ${_formatDate(joinedAt)}' : user.email ?? '',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Items Lent',
                    value: lentCount.toString(),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TransactionHistoryPage(
                            userId: user.uid,
                            title: 'Items Lent',
                            roleFilter: TransactionRole.lent,
                            initialTransactions: lentTransactions,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    label: 'Items Borrowed',
                    value: borrowedCount.toString(),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TransactionHistoryPage(
                            userId: user.uid,
                            title: 'Items Borrowed',
                            roleFilter: TransactionRole.borrowed,
                            initialTransactions: borrowedTransactions,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Settings'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: auth.isBusy ? null : auth.signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Log out'),
            ),
            if (snapshot.connectionState == ConnectionState.waiting) ...[
              const SizedBox(height: 18),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        );
      },
    );
  }

  Future<void> _changeProfilePhoto() async {
    final auth = context.read<AuthController>();
    final user = auth.firebaseUser;
    if (user == null) {
      _showMessage('Please sign in again.');
      return;
    }

    try {
      final image = await pickAndCropImage(
        context: context,
        imagePicker: _imagePicker,
        cropTitle: 'Crop profile photo',
        circleUi: true,
        aspectRatio: 1,
        maxWidth: 1400,
        imageQuality: 88,
      );
      if (!mounted || image == null) {
        return;
      }

      setState(() {
        _photoUpdating = true;
      });

      final photoUrl = await context.read<OnboardingService>().uploadProfilePhoto(
            uid: user.uid,
            image: image,
          );
      await user.updatePhotoURL(photoUrl);
      await user.reload();
      await context.read<UserService>().updateProfilePhoto(
            uid: user.uid,
            photoUrl: photoUrl,
          );

      if (!mounted) {
        return;
      }
      _showMessage('Profile picture updated.');
    } on PlatformException {
      if (!mounted) {
        return;
      }
      _showMessage('Photo picker is unavailable right now.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not update profile picture: $error');
    } finally {
      if (mounted) {
        setState(() {
          _photoUpdating = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day/${date.year}';
  }
}

class _EditableProfileAvatar extends StatelessWidget {
  const _EditableProfileAvatar({
    required this.photoUrl,
    required this.onEdit,
    required this.isBusy,
  });

  final String photoUrl;
  final VoidCallback? onEdit;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: Theme.of(context).colorScheme.surfaceVariant,
      alignment: Alignment.center,
      child: const Icon(Icons.person_outline, size: 34),
    );

    return Column(
      children: [
        SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipOval(
                  child: photoUrl.isEmpty
                      ? fallback
                      : Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => fallback,
                        ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: FilledButton.tonal(
                  onPressed: onEdit,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(34, 34),
                  ),
                  child: isBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_outlined, size: 16),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
