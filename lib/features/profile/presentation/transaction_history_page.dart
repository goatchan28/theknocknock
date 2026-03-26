import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_transaction.dart';
import '../../../services/listing_service.dart';
import '../../listings/presentation/listing_detail_page.dart';

class TransactionHistoryPage extends StatelessWidget {
  const TransactionHistoryPage({
    super.key,
    required this.userId,
    required this.title,
    required this.roleFilter,
    this.initialTransactions = const <UserTransaction>[],
  });

  final String userId;
  final String title;
  final TransactionRole roleFilter;
  final List<UserTransaction> initialTransactions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StreamBuilder<List<UserTransaction>>(
        initialData: initialTransactions,
        stream: context.read<ListingService>().watchUserTransactions(userId),
        builder: (context, snapshot) {
          final transactions = (snapshot.data ?? const <UserTransaction>[])
              .where((tx) => tx.role == roleFilter)
              .toList();
          if (snapshot.connectionState == ConnectionState.waiting &&
              transactions.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (transactions.isEmpty) {
            return Center(
              child: Text(
                roleFilter == TransactionRole.lent
                    ? 'No items lent yet.'
                    : 'No items borrowed yet.',
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final tx = transactions[index];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ListingDetailPage(listingId: tx.listingId),
                    ),
                  );
                },
                child: Ink(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tx.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tx.category,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _timeText(tx.acceptedAt),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemCount: transactions.length,
          );
        },
      ),
    );
  }

  String _timeText(DateTime? dateTime) {
    if (dateTime == null) {
      return 'Completed recently';
    }
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) {
      return 'Completed just now';
    }
    if (diff.inHours < 1) {
      return 'Completed ${diff.inMinutes}m ago';
    }
    if (diff.inDays < 1) {
      return 'Completed ${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return 'Completed ${diff.inDays}d ago';
    }
    final weeks = (diff.inDays / 7).floor();
    return 'Completed ${weeks}w ago';
  }
}
