import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/listing.dart';
import '../../../models/public_profile.dart';
import '../../../services/listing_service.dart';
import '../../../services/public_profile_service.dart';
import '../../listings/presentation/listing_detail_page.dart';

class PublicProfilePage extends StatelessWidget {
  const PublicProfilePage({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  Widget build(BuildContext context) {
    final profileService = context.read<PublicProfileService>();
    final listingService = context.read<ListingService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<PublicProfile?>(
        stream: profileService.watchPublicProfile(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final profile = snapshot.data;
          if (profile == null) {
            return const Center(child: Text('Profile unavailable.'));
          }

          return StreamBuilder<List<Listing>>(
            stream: listingService.watchOwnerListings(userId),
            builder: (context, listingSnapshot) {
              final listings = listingSnapshot.data ?? const <Listing>[];
              final activeCount =
                  listings.where((listing) => listing.status == ListingStatus.active).length;
              final inUseCount =
                  listings.where((listing) => listing.status != ListingStatus.active).length;

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 42,
                      backgroundImage: profile.photoUrl != null
                          ? NetworkImage(profile.photoUrl!)
                          : null,
                      child: profile.photoUrl == null
                          ? const Icon(Icons.person_outline, size: 34)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      profile.displayName,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (profile.createdAt != null)
                    Center(
                      child: Text(
                        'Joined ${_formatDate(profile.createdAt!)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniStatCard(
                          label: 'Listings',
                          value: listings.length.toString(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MiniStatCard(
                          label: 'Active',
                          value: activeCount.toString(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MiniStatCard(
                          label: 'In Use',
                          value: inUseCount.toString(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Recent listings',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (listingSnapshot.connectionState == ConnectionState.waiting &&
                      listings.isEmpty)
                    const Center(child: CircularProgressIndicator())
                  else if (listings.isEmpty)
                    const Text('No listings yet.')
                  else
                    ...listings.take(8).map(
                          (listing) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _PublicListingRow(listing: listing),
                          ),
                        ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day/${date.year}';
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _PublicListingRow extends StatelessWidget {
  const _PublicListingRow({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ListingDetailPage(listingId: listing.id),
          ),
        );
      },
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    listing.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    listing.type == ListingType.lend ? 'Lend' : 'Borrow',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              listing.category,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              _metaText(listing),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  String _metaText(Listing listing) {
    final statusLabel = switch (listing.status) {
      ListingStatus.active => 'Active',
      ListingStatus.archived => 'In Use',
      ListingStatus.sold => 'In Use',
    };
    final posted = _timeText(listing.createdAt);
    return '$statusLabel · $posted';
  }

  String _timeText(DateTime? dateTime) {
    if (dateTime == null) {
      return 'Posted recently';
    }
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) {
      return 'Posted just now';
    }
    if (diff.inHours < 1) {
      return 'Posted ${diff.inMinutes}m ago';
    }
    if (diff.inDays < 1) {
      return 'Posted ${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return 'Posted ${diff.inDays}d ago';
    }
    final weeks = (diff.inDays / 7).floor();
    return 'Posted ${weeks}w ago';
  }
}
