import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_user.dart';
import '../../../models/listing.dart';
import '../../../models/listing_offer.dart';
import '../../../providers/auth_controller.dart';
import '../../../services/listing_service.dart';
import '../../../services/user_service.dart';
import '../../my_listings/presentation/manage_listing_page.dart';
import '../../profile/presentation/public_profile_page.dart';

class ListingDetailPage extends StatelessWidget {
  const ListingDetailPage({
    super.key,
    required this.listingId,
  });

  final String listingId;

  @override
  Widget build(BuildContext context) {
    final listingService = context.read<ListingService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Listing')),
      body: StreamBuilder<Listing?>(
        stream: listingService.watchListing(listingId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final listing = snapshot.data;
          if (listing == null) {
            return const Center(child: Text('This listing is unavailable.'));
          }

          return _ListingBody(listing: listing);
        },
      ),
    );
  }
}

class _ListingBody extends StatelessWidget {
  const _ListingBody({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final listingService = context.read<ListingService>();
    final currentUserId = auth.firebaseUser?.uid;
    final typeTone = _typeTone(context, listing.type);
    final statusTone = _statusTone(context, listing.status);
    final urgentTone = _urgentTone(context);

    if (currentUserId == null) {
      return const Center(child: Text('Please sign in again.'));
    }

    final isOwner = listing.ownerId == currentUserId;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ListingImage(imageUrl: listing.imageUrl),
        const SizedBox(height: 16),
        Text(listing.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              label: Text(listing.type == ListingType.borrow ? 'Borrow' : 'Lend'),
              backgroundColor: typeTone.background,
              side: BorderSide(color: typeTone.border),
              labelStyle: TextStyle(
                color: typeTone.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
            Chip(
              label: Text(_statusLabel(listing.status)),
              backgroundColor: statusTone.background,
              side: BorderSide(color: statusTone.border),
              labelStyle: TextStyle(
                color: statusTone.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
            Chip(label: Text(listing.category)),
            if (listing.isUrgent)
              Chip(
                label: Text(
                  'Urgent · ${_formatUrgentTimeLeft(listing.urgentUntil)} left',
                ),
                backgroundColor: urgentTone.background,
                side: BorderSide(color: urgentTone.border),
                labelStyle: TextStyle(
                  color: urgentTone.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          listing.description.isEmpty
              ? 'No description provided.'
              : listing.description,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 6),
        Text(
          _formatTimeAgo(listing.createdAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (listing.isBorrow && listing.isUrgent)
          Text(
            'Urgent request expires in ${_formatUrgentTimeLeft(listing.urgentUntil)}.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PublicProfilePage(userId: listing.ownerId),
                ),
              );
            },
            leading: CircleAvatar(
              backgroundImage: listing.ownerPhotoUrl != null
                  ? NetworkImage(listing.ownerPhotoUrl!)
                  : null,
              child: listing.ownerPhotoUrl == null
                  ? const Icon(Icons.person_outline)
                  : null,
            ),
            title: Text(listing.ownerDisplayName),
            subtitle: const Text('View profile'),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
        const SizedBox(height: 18),
        if (isOwner)
          _OwnerActionSection(listing: listing)
        else
          StreamBuilder<ListingOffer?>(
            stream: listingService.watchMyOfferForListing(
              listingId: listing.id,
              requesterId: currentUserId,
            ),
            builder: (context, offerSnapshot) {
              final offer = offerSnapshot.data;
              return _OffererActionSection(
                listing: listing,
                offer: offer,
                currentUserId: currentUserId,
              );
            },
          ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => _showReportDialog(
            context,
            listingService: listingService,
            listingId: listing.id,
            reporterId: currentUserId,
          ),
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Report listing'),
        ),
      ],
    );
  }

  Future<void> _showReportDialog(
    BuildContext context, {
    required ListingService listingService,
    required String listingId,
    required String reporterId,
  }) async {
    final reasonController = TextEditingController();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Report listing'),
          content: TextField(
            controller: reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Tell us what is wrong with this listing.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );

    if (submitted != true || !context.mounted) {
      return;
    }

    final reason = reasonController.text.trim().isEmpty
        ? 'No additional details.'
        : reasonController.text.trim();

    await listingService.submitListingReport(
      listingId: listingId,
      reporterId: reporterId,
      reason: reason,
    );

    if (!context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(const SnackBar(content: Text('Report submitted.')));
  }

  String _statusLabel(ListingStatus status) {
    switch (status) {
      case ListingStatus.active:
        return 'Active';
      case ListingStatus.archived:
        return 'Archived';
      case ListingStatus.sold:
        return 'Sold';
    }
  }

  _ChipTone _typeTone(BuildContext context, ListingType type) {
    final scheme = Theme.of(context).colorScheme;
    switch (type) {
      case ListingType.lend:
        return _ChipTone(
          background: scheme.tertiaryContainer,
          foreground: scheme.onTertiaryContainer,
        );
      case ListingType.borrow:
        return _ChipTone(
          background: scheme.secondaryContainer,
          foreground: scheme.onSecondaryContainer,
        );
    }
  }

  _ChipTone _statusTone(BuildContext context, ListingStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case ListingStatus.active:
        return _ChipTone(
          background: scheme.primaryContainer,
          foreground: scheme.onPrimaryContainer,
        );
      case ListingStatus.sold:
        return _ChipTone(
          background: Colors.green.shade100,
          foreground: Colors.green.shade900,
        );
      case ListingStatus.archived:
        return _ChipTone(
          background: scheme.surfaceVariant,
          foreground: scheme.onSurfaceVariant,
        );
    }
  }

  _ChipTone _urgentTone(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ChipTone(
      background: scheme.errorContainer,
      foreground: scheme.onErrorContainer,
    );
  }
}

class _OwnerActionSection extends StatelessWidget {
  const _OwnerActionSection({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    if (listing.isSold || !listing.isActive) {
      return _UnavailableCard(status: listing.status);
    }

    return FilledButton.icon(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ManageListingPage(listingId: listing.id),
          ),
        );
      },
      icon: const Icon(Icons.settings_outlined),
      label: const Text('Manage item'),
    );
  }
}

class _OffererActionSection extends StatelessWidget {
  const _OffererActionSection({
    required this.listing,
    required this.offer,
    required this.currentUserId,
  });

  final Listing listing;
  final ListingOffer? offer;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    if (offer?.status == OfferStatus.accepted) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Offer accepted'),
          ),
          const SizedBox(height: 10),
          _AcceptedContactCard(userId: listing.ownerId),
        ],
      );
    }

    if (listing.isSold || !listing.isActive) {
      return _UnavailableCard(status: listing.status);
    }

    if (offer?.isPending == true) {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.hourglass_top_outlined),
        label: const Text('Offer pending'),
      );
    }

    return FilledButton.icon(
      onPressed: () => _makeOffer(context),
      icon: const Icon(Icons.local_offer_outlined),
      label: const Text('Make offer'),
    );
  }

  Future<void> _makeOffer(BuildContext context) async {
    final acceptedLiability = await _showLiabilityDialog(context);
    if (acceptedLiability != true || !context.mounted) {
      return;
    }

    try {
      final listingService = context.read<ListingService>();
      final result = await listingService.makeOffer(
        listingId: listing.id,
        requesterId: currentUserId,
        liabilityAccepted: true,
      );

      if (!context.mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();

      switch (result) {
        case MakeOfferResult.created:
          messenger.showSnackBar(
            const SnackBar(content: Text('Offer submitted. Waiting for owner response.')),
          );
          break;
        case MakeOfferResult.alreadyPending:
          messenger.showSnackBar(
            const SnackBar(content: Text('You already have a pending offer for this listing.')),
          );
          break;
        case MakeOfferResult.listingUnavailable:
          messenger.showSnackBar(
            const SnackBar(content: Text('This listing is no longer available.')),
          );
          break;
        case MakeOfferResult.ownListing:
          messenger.showSnackBar(
            const SnackBar(content: Text('You cannot offer on your own listing.')),
          );
          break;
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(content: Text('Could not make offer: $error')),
      );
    }
  }

  Future<bool?> _showLiabilityDialog(BuildContext context) {
    bool agreed = false;

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Liability terms'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'By continuing, you agree to use this item responsibly and return '
                    'it in fair condition as agreed with the owner.',
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: agreed,
                    onChanged: (value) {
                      setState(() {
                        agreed = value ?? false;
                      });
                    },
                    title: const Text('I agree to these terms.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: agreed ? () => Navigator.of(context).pop(true) : null,
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
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

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({required this.status});

  final ListingStatus status;

  @override
  Widget build(BuildContext context) {
    final label = status == ListingStatus.sold
        ? 'This listing has been marked as sold.'
        : 'This listing is currently unavailable.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label),
    );
  }
}

class _ListingImage extends StatelessWidget {
  const _ListingImage({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surfaceVariant,
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_outlined, size: 40),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        imageUrl!,
        height: 220,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            height: 220,
            color: Theme.of(context).colorScheme.surfaceVariant,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, size: 40),
          );
        },
      ),
    );
  }
}

String _formatTimeAgo(DateTime? dateTime) {
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

String _formatUrgentTimeLeft(DateTime? urgentUntil) {
  if (urgentUntil == null) {
    return 'soon';
  }

  final diff = urgentUntil.difference(DateTime.now());
  if (diff <= Duration.zero) {
    return 'ending';
  }
  if (diff.inMinutes < 1) {
    return '<1m';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes}m';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours}h';
  }
  return '${diff.inDays}d';
}

class _ChipTone {
  const _ChipTone({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;

  Color get border => foreground.withOpacity(0.28);
}
