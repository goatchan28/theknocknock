import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_user.dart';
import '../../../models/listing.dart';
import '../../../models/listing_offer.dart';
import '../../../models/public_profile.dart';
import '../../../providers/auth_controller.dart';
import '../../../services/listing_service.dart';
import '../../../services/public_profile_service.dart';
import '../../../services/user_service.dart';
import '../../listings/presentation/listing_detail_page.dart';
import '../../listings/presentation/listing_form_page.dart';
import '../../profile/presentation/public_profile_page.dart';

class ManageListingPage extends StatelessWidget {
  const ManageListingPage({
    super.key,
    required this.listingId,
  });

  final String listingId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Listing')),
      body: StreamBuilder<Listing?>(
        stream: context.read<ListingService>().watchListing(listingId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final listing = snapshot.data;
          if (listing == null) {
            return const Center(child: Text('This listing is unavailable.'));
          }

          return _ManageBody(listing: listing);
        },
      ),
    );
  }
}

class _ManageBody extends StatefulWidget {
  const _ManageBody({required this.listing});

  final Listing listing;

  @override
  State<_ManageBody> createState() => _ManageBodyState();
}

class _ManageBodyState extends State<_ManageBody> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InkWell(
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
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: _ListingThumb(imageUrl: listing.imageUrl),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listing.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        listing.category,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Chip(label: Text(_statusLabel(listing.status))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.tonalIcon(
          onPressed: _busy
              ? null
              : () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ListingFormPage.edit(listing: listing),
                    ),
                  );
                },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit listing'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : () => _toggleArchive(listing),
          icon: Icon(
            listing.status == ListingStatus.archived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined,
          ),
          label: Text(
            listing.status == ListingStatus.archived
                ? (listing.hasAcceptedMatch || listing.archivedFromSold
                    ? 'Unarchive to sold'
                    : 'Unarchive listing')
                : listing.status == ListingStatus.sold
                    ? 'Archive sold listing'
                    : 'Archive listing',
          ),
        ),
        const SizedBox(height: 20),
        StreamBuilder<List<ListingOffer>>(
          stream: context.read<ListingService>().watchIncomingOffersForListing(
                listingId: listing.id,
                ownerId: listing.ownerId,
              ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final offers = snapshot.data ?? const <ListingOffer>[];
            final visibleOffers = offers
                .where(
                  (offer) =>
                      offer.status == OfferStatus.pending ||
                      offer.status == OfferStatus.accepted,
                )
                .toList();
            final pendingCount = visibleOffers
                .where((offer) => offer.status == OfferStatus.pending)
                .length;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Incoming offers',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text('$pendingCount pending'),
                    const SizedBox(height: 10),
                    if (visibleOffers.isEmpty)
                      const Text('No active offers for this listing.')
                    else
                      ...visibleOffers.map(
                        (offer) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _IncomingOfferTile(
                            offer: offer,
                            busy: _busy,
                            onAccept: () => _acceptOffer(offer),
                            onDecline: () => _declineOffer(offer),
                            onOpenRequesterProfile: () =>
                                _openRequesterProfile(offer.requesterId),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _acceptOffer(ListingOffer offer) async {
    if (offer.status != OfferStatus.pending) {
      return;
    }

    final uid = context.read<AuthController>().firebaseUser?.uid;
    if (uid == null) {
      _showMessage('Session expired. Please sign in again.');
      return;
    }

    final agreed = await _showOwnerLiabilityDialog();
    if (agreed != true || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await context.read<ListingService>().acceptIncomingOffer(
            listingId: widget.listing.id,
            offerId: offer.id,
            ownerId: uid,
          );
      if (!mounted) {
        return;
      }
      _showMessage('Offer accepted. Listing marked as sold.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not accept offer: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _declineOffer(ListingOffer offer) async {
    if (offer.status != OfferStatus.pending) {
      return;
    }

    final uid = context.read<AuthController>().firebaseUser?.uid;
    if (uid == null) {
      _showMessage('Session expired. Please sign in again.');
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await context.read<ListingService>().declineIncomingOffer(
            offerId: offer.id,
            ownerId: uid,
          );
      if (!mounted) {
        return;
      }
      _showMessage('Offer declined.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not decline offer: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<bool?> _showOwnerLiabilityDialog() {
    bool agreed = false;

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Confirm acceptance terms'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'By accepting, you confirm this match and acknowledge that '
                    'contact info will be revealed to both of you.',
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
                    title: const Text('I agree and want to accept this offer.'),
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
                  child: const Text('Accept'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleArchive(Listing listing) async {
    final uid = context.read<AuthController>().firebaseUser?.uid;
    if (uid == null) {
      _showMessage('Session expired. Please sign in again.');
      return;
    }

    setState(() {
      _busy = true;
    });

    final reopeningToSold =
        listing.status == ListingStatus.archived &&
            (listing.hasAcceptedMatch || listing.archivedFromSold);
    final shouldArchive = listing.status != ListingStatus.archived;

    try {
      await context.read<ListingService>().setListingArchived(
            listingId: listing.id,
            ownerId: uid,
            archived: shouldArchive,
          );
      if (!mounted) {
        return;
      }
      _showMessage(
        shouldArchive
            ? 'Listing archived.'
            : reopeningToSold
                ? 'Listing unarchived to sold.'
                : 'Listing unarchived.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not update listing: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _openRequesterProfile(String userId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicProfilePage(userId: userId),
      ),
    );
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
}

class _IncomingOfferTile extends StatelessWidget {
  const _IncomingOfferTile({
    required this.offer,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    required this.onOpenRequesterProfile,
  });

  final ListingOffer offer;
  final bool busy;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;
  final VoidCallback onOpenRequesterProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _RequesterHeader(
                  requesterId: offer.requesterId,
                  onTap: onOpenRequesterProfile,
                ),
              ),
              _OfferStatusChip(status: offer.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _timeText(offer.createdAt),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (offer.status == OfferStatus.pending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onDecline,
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : onAccept,
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ] else if (offer.status == OfferStatus.accepted) ...[
            const SizedBox(height: 10),
            _AcceptedContactCard(userId: offer.requesterId),
          ],
        ],
      ),
    );
  }

  String _timeText(DateTime? dateTime) {
    if (dateTime == null) {
      return 'Received recently';
    }
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) {
      return 'Received just now';
    }
    if (diff.inHours < 1) {
      return 'Received ${diff.inMinutes}m ago';
    }
    if (diff.inDays < 1) {
      return 'Received ${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return 'Received ${diff.inDays}d ago';
    }
    final weeks = (diff.inDays / 7).floor();
    return 'Received ${weeks}w ago';
  }
}

class _RequesterHeader extends StatelessWidget {
  const _RequesterHeader({
    required this.requesterId,
    required this.onTap,
  });

  final String requesterId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final profileService = context.read<PublicProfileService>();
    return StreamBuilder<PublicProfile?>(
      stream: profileService.watchPublicProfile(requesterId),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final displayName = (profile?.displayName ?? '').trim().isNotEmpty
            ? profile!.displayName.trim()
            : _shortRequester(requesterId);
        final photoUrl = (profile?.photoUrl ?? '').trim();

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                  child: photoUrl.isEmpty
                      ? const Icon(Icons.person_outline, size: 14)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  String _shortRequester(String uid) {
    if (uid.length <= 8) {
      return uid;
    }
    return '${uid.substring(0, 8)}...';
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

class _OfferStatusChip extends StatelessWidget {
  const _OfferStatusChip({required this.status});

  final OfferStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      OfferStatus.pending => Theme.of(context).colorScheme.secondaryContainer,
      OfferStatus.accepted => Colors.green.shade100,
      OfferStatus.declined => Theme.of(context).colorScheme.errorContainer,
    };

    final label = switch (status) {
      OfferStatus.pending => 'Pending',
      OfferStatus.accepted => 'Accepted',
      OfferStatus.declined => 'Declined',
    };

    return Chip(
      backgroundColor: color,
      label: Text(label),
    );
  }
}

class _ListingThumb extends StatelessWidget {
  const _ListingThumb({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceVariant,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_outlined),
      );
    }

    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return Container(
          color: Theme.of(context).colorScheme.surfaceVariant,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined),
        );
      },
    );
  }
}
