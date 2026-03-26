import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_transaction.dart';
import '../../../providers/auth_controller.dart';
import '../../../services/listing_service.dart';
import 'settings_page.dart';
import 'transaction_history_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

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
              child: CircleAvatar(
                radius: 42,
                backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: photoUrl.isEmpty
                    ? const Icon(Icons.person_outline, size: 34)
                    : null,
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

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day/${date.year}';
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
