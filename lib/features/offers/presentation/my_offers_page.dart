import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_user.dart';
import '../../../models/listing.dart';
import '../../../models/listing_offer.dart';
import '../../../providers/auth_controller.dart';
import '../../../services/listing_service.dart';
import '../../../services/user_service.dart';
import '../../listings/presentation/listing_detail_page.dart';

class MyOffersPage extends StatefulWidget {
  const MyOffersPage({super.key});

  @override
  State<MyOffersPage> createState() => _MyOffersPageState();
}

class _MyOffersPageState extends State<MyOffersPage> {
  final _searchController = TextEditingController();
  final Set<OfferStatus> _selectedStatuses = {
    OfferStatus.pending,
    OfferStatus.accepted,
    OfferStatus.declined,
  };

  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final requesterId = auth.firebaseUser?.uid;

    if (requesterId == null) {
      return const Center(child: Text('Please sign in again.'));
    }

    final listingService = context.read<ListingService>();

    return StreamBuilder<List<ListingOffer>>(
      stream: listingService.watchMyOffers(requesterId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final offers = snapshot.data ?? const <ListingOffer>[];
        final visibleOffers = offers
            .where((offer) => _selectedStatuses.contains(offer.status))
            .toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSearchAndFilterBar(),
            const SizedBox(height: 10),
            _buildActiveFilterChip(),
            const SizedBox(height: 16),
            if (offers.isEmpty)
              const _EmptyState(
                message: 'No offers yet. Browse listings and tap Make offer.',
              )
            else if (visibleOffers.isEmpty)
              const _EmptyState(
                message: 'No offers match this status filter.',
              )
            else
              ...visibleOffers.map(
                (offer) => _OfferRow(
                  offer: offer,
                  searchText: _search,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSearchAndFilterBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search offer by item name',
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _search = '';
                        });
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (value) {
              setState(() {
                _search = value.trim().toLowerCase();
              });
            },
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.tonalIcon(
          onPressed: _openStatusFilterSheet,
          icon: const Icon(Icons.tune),
          label: const Text('Filter'),
        ),
      ],
    );
  }

  Widget _buildActiveFilterChip() {
    final label = switch (_selectedStatuses.length) {
      3 => 'Status: All',
      _ => 'Status: ${_selectedStatuses.map(_statusLabel).join(', ')}',
    };

    return Chip(label: Text(label));
  }

  Future<void> _openStatusFilterSheet() async {
    final result = await showModalBottomSheet<Set<OfferStatus>>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final tempStatuses = <OfferStatus>{..._selectedStatuses};

        return StatefulBuilder(
          builder: (context, setSheetState) {
            void toggleStatus(OfferStatus status, bool selected) {
              setSheetState(() {
                if (selected) {
                  tempStatuses.add(status);
                } else if (tempStatuses.length > 1) {
                  tempStatuses.remove(status);
                }
              });
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Offer Status',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    ...OfferStatus.values.map(
                      (status) => CheckboxListTile(
                        value: tempStatuses.contains(status),
                        onChanged: (value) => toggleStatus(status, value ?? false),
                        title: Text(_statusLabel(status)),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).pop(OfferStatus.values.toSet());
                            },
                            child: const Text('Clear'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(tempStatuses),
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _selectedStatuses
        ..clear()
        ..addAll(result);
    });
  }

  String _statusLabel(OfferStatus status) {
    switch (status) {
      case OfferStatus.pending:
        return 'Pending';
      case OfferStatus.accepted:
        return 'Accepted';
      case OfferStatus.declined:
        return 'Declined';
    }
  }

}

class _OfferRow extends StatelessWidget {
  const _OfferRow({
    required this.offer,
    required this.searchText,
  });

  final ListingOffer offer;
  final String searchText;

  @override
  Widget build(BuildContext context) {
    final listingService = context.read<ListingService>();

    return StreamBuilder<Listing?>(
      stream: listingService.watchListing(offer.listingId),
      builder: (context, listingSnapshot) {
        final listing = listingSnapshot.data;
        final title = listing?.title.trim().isNotEmpty == true
            ? listing!.title
            : 'Listing unavailable';

        if (searchText.isNotEmpty && !title.toLowerCase().contains(searchText)) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ListingDetailPage(listingId: offer.listingId),
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
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(status: offer.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    listing?.category ?? 'Unknown category',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _timeText(offer.createdAt),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  if (offer.status == OfferStatus.accepted) ...[
                    const SizedBox(height: 10),
                    _AcceptedContactCard(userId: offer.ownerId),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _timeText(DateTime? dateTime) {
    if (dateTime == null) {
      return 'Sent recently';
    }

    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) {
      return 'Sent just now';
    }
    if (diff.inHours < 1) {
      return 'Sent ${diff.inMinutes}m ago';
    }
    if (diff.inDays < 1) {
      return 'Sent ${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return 'Sent ${diff.inDays}d ago';
    }
    final weeks = (diff.inDays / 7).floor();
    return 'Sent ${weeks}w ago';
  }
}

class _AcceptedContactCard extends StatelessWidget {
  const _AcceptedContactCard({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final userService = context.read<UserService>();
    return StreamBuilder<AppUser?>(
      stream: userService.watchUser(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _ContactContainer(
            title: 'Matched contact',
            subtitle: 'Loading contact...',
          );
        }
        if (snapshot.hasError) {
          return const _ContactContainer(
            title: 'Matched contact',
            subtitle: 'Contact unlock pending.',
          );
        }

        final user = snapshot.data;
        final name = (user?.displayName ?? '').trim().isNotEmpty
            ? user!.displayName!.trim()
            : 'Columbia Student';
        final phone = (user?.phoneNumber ?? '').trim();

        return _ContactContainer(
          title: 'Matched contact',
          subtitle: '$name\n${phone.isEmpty ? 'Phone unavailable' : phone}',
        );
      },
    );
  }
}

class _ContactContainer extends StatelessWidget {
  const _ContactContainer({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.contact_phone_outlined, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final OfferStatus status;

  @override
  Widget build(BuildContext context) {
    Color? color;
    switch (status) {
      case OfferStatus.pending:
        color = Theme.of(context).colorScheme.secondaryContainer;
        break;
      case OfferStatus.accepted:
        color = Colors.green.shade100;
        break;
      case OfferStatus.declined:
        color = Theme.of(context).colorScheme.errorContainer;
        break;
    }

    return Chip(
      backgroundColor: color,
      label: Text(
        switch (status) {
          OfferStatus.pending => 'Pending',
          OfferStatus.accepted => 'Accepted',
          OfferStatus.declined => 'Declined',
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(message),
    );
  }
}
