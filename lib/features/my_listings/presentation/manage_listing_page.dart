import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/input_formatters/us_phone_input_formatter.dart';
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
import '../../listings/presentation/create_listing_sheet.dart';
import '../../listings/presentation/create_listing_flow_result.dart';
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
    final statusTone = _statusTone(context, listing.status);
    final urgentTone = _urgentTone(context);
    final isMatchedOrInUse =
        listing.status == ListingStatus.sold ||
        listing.hasAcceptedMatch ||
        listing.archivedFromSold;
    final isReturnedLocked = listing.returnedFromMatch;
    final isInUseNow =
        listing.status == ListingStatus.sold && listing.pickedUpAt != null;
    final isArchiveAction = listing.status != ListingStatus.archived;
    final archiveDisabledForInUse = isArchiveAction && isInUseNow;
    final showUrgentTimerExpiredHint =
        listing.isBorrow &&
        listing.status == ListingStatus.active &&
        listing.isUrgent &&
        !listing.hasUrgentTimer;

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
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (listing.isBorrow &&
                              listing.status == ListingStatus.active &&
                              listing.isUrgent)
                            Chip(
                              label: Text(_urgentLabel(listing)),
                              backgroundColor: urgentTone.background,
                              side: BorderSide(color: urgentTone.border),
                              labelStyle: TextStyle(
                                color: urgentTone.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          Chip(
                            label: Text(_statusLabel(listing)),
                            backgroundColor: statusTone.background,
                            side: BorderSide(color: statusTone.border),
                            labelStyle: TextStyle(
                              color: statusTone.foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
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
          onPressed: _busy || isMatchedOrInUse || isReturnedLocked
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
        if (isMatchedOrInUse) ...[
          const SizedBox(height: 6),
          Text(
            'Editing is disabled while this item is matched or in use.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ] else if (isReturnedLocked) ...[
          const SizedBox(height: 6),
          Text(
            'Returned listings cannot be edited. Relist instead.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (showUrgentTimerExpiredHint) ...[
          const SizedBox(height: 6),
          Text(
            'Urgent timer expired. You can edit listing and save changes to reset the timer.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: _busy || archiveDisabledForInUse
              ? null
              : listing.returnedFromMatch
              ? () => _promptRelistFlow(sourceListing: listing)
              : () => _toggleArchive(listing),
          icon: Icon(
            listing.returnedFromMatch
                ? Icons.refresh_outlined
                : listing.status == ListingStatus.archived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined,
          ),
          label: Text(
            listing.returnedFromMatch
                ? 'Relist listing'
                : listing.status == ListingStatus.archived
                ? 'Unarchive listing'
                : listing.status == ListingStatus.sold
                    ? (listing.pickedUpAt == null
                        ? 'Archive matched listing'
                        : 'Archive in-use listing')
                    : 'Archive listing',
          ),
        ),
        if (archiveDisabledForInUse) ...[
          const SizedBox(height: 6),
          Text(
            'In-use listings cannot be archived.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
                            listing: listing,
                            offer: offer,
                            busy: _busy,
                            onAccept: () => _acceptOffer(offer),
                            onDecline: () => _declineOffer(offer),
                            onMarkPickedUp: () =>
                                _markAcceptedOfferPickedUp(listing: listing, offer: offer),
                            onMarkReturned: () =>
                                _markAcceptedOfferReturned(listing: listing, offer: offer),
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
      _showMessage('Offer accepted. Listing is now matched.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      final recovered = await _didAcceptSucceedDespiteError(offer.id);
      if (!mounted) {
        return;
      }
      if (recovered) {
        _showMessage('Offer accepted. Listing is now matched.');
      } else {
        _showMessage('Could not accept offer: $error');
      }
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

  Future<void> _markAcceptedOfferPickedUp({
    required Listing listing,
    required ListingOffer offer,
  }) async {
    final uid = context.read<AuthController>().firebaseUser?.uid;
    if (uid == null) {
      _showMessage('Session expired. Please sign in again.');
      return;
    }

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'When should this item be returned?',
    );

    if (selectedDate == null || !mounted) {
      return;
    }

    final dueAt = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      23,
      59,
    );

    setState(() {
      _busy = true;
    });
    try {
      await context.read<ListingService>().markOfferPickedUp(
            offerId: offer.id,
            actorId: uid,
            returnDueAt: dueAt,
          );
      if (!mounted) {
        return;
      }
      _showMessage('Marked as picked up.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not mark picked up: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _markAcceptedOfferReturned({
    required Listing listing,
    required ListingOffer offer,
  }) async {
    final uid = context.read<AuthController>().firebaseUser?.uid;
    if (uid == null) {
      _showMessage('Session expired. Please sign in again.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark item as returned?'),
        content: const Text(
          'This closes the active match for this listing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark returned'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      await context.read<ListingService>().markOfferReturned(
            offerId: offer.id,
            actorId: uid,
          );
      if (!mounted) {
        return;
      }
      _showMessage('Marked as returned.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not mark returned: $error');
      return;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }

    if (!listing.isLend) {
      return;
    }

    await _promptRelistFlow(sourceListing: listing);
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
            : 'Listing unarchived and relisted as active.',
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

  Future<bool> _didAcceptSucceedDespiteError(String offerId) async {
    try {
      final service = context.read<ListingService>();
      final offer = await service.getOfferById(offerId);
      if (offer?.status == OfferStatus.accepted) {
        return true;
      }

      final listing = await service.getListingById(widget.listing.id);
      return listing != null &&
          listing.status == ListingStatus.sold &&
          listing.acceptedOfferId == offerId;
    } catch (_) {
      return false;
    }
  }

  Future<void> _relistNow({required Listing sourceListing}) async {
    final uid = context.read<AuthController>().firebaseUser?.uid;
    if (uid == null) {
      _showMessage('Session expired. Please sign in again.');
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      final newListingId = await context.read<ListingService>().relistFromListing(
            sourceListingId: sourceListing.id,
            ownerId: uid,
          );
      if (!mounted) {
        return;
      }
      _showMessage('Relisted successfully.');
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ManageListingPage(listingId: newListingId),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not relist: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _promptRelistFlow({required Listing sourceListing}) async {
    final relistAction = await _showRelistSheet();
    if (!mounted || relistAction == null) {
      return;
    }

    switch (relistAction) {
      case _RelistAction.now:
        await _relistNow(sourceListing: sourceListing);
        return;
      case _RelistAction.withEdits:
        await _openRelistWithEdits(sourceListing: sourceListing);
        return;
    }
  }

  Future<void> _openRelistWithEdits({required Listing sourceListing}) async {
    final result = await showCreateListingSheet(
      context,
      prefillListing: sourceListing,
      title: 'Relist Listing',
    );

    if (!mounted || result == null) {
      return;
    }

    if (result.action == CreateListingNextAction.done) {
      _showMessage('Relisted successfully.');
      return;
    }

    final listingId = result.listingId?.trim() ?? '';
    if (listingId.isEmpty) {
      return;
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ManageListingPage(listingId: listingId),
      ),
    );
  }

  Future<_RelistAction?> _showRelistSheet() {
    return showModalBottomSheet<_RelistAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Item returned',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text('Do you want to relist this item now?'),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(_RelistAction.now),
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('Relist now'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(_RelistAction.withEdits),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Relist with edits'),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        );
      },
    );
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

  String _statusLabel(Listing listing) {
    if (listing.returnedFromMatch) {
      return 'Returned';
    }
    switch (listing.status) {
      case ListingStatus.active:
        return 'Active';
      case ListingStatus.archived:
        return 'Archived';
      case ListingStatus.sold:
        return listing.pickedUpAt == null ? 'Matched' : 'In Use';
    }
  }

  _ListingTagTone _statusTone(BuildContext context, ListingStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case ListingStatus.active:
        return _ListingTagTone(
          background: scheme.primaryContainer,
          foreground: scheme.onPrimaryContainer,
        );
      case ListingStatus.sold:
        return _ListingTagTone(
          background: Colors.green.shade100,
          foreground: Colors.green.shade900,
        );
      case ListingStatus.archived:
        return _ListingTagTone(
          background: scheme.surfaceVariant,
          foreground: scheme.onSurfaceVariant,
        );
    }
  }

  _ListingTagTone _urgentTone(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ListingTagTone(
      background: scheme.errorContainer,
      foreground: scheme.onErrorContainer,
    );
  }

  String _urgentLabel(Listing listing) {
    if (listing.hasUrgentTimer && listing.urgentUntil != null) {
      return 'Urgent · ${_formatUrgentTimeLeft(listing.urgentUntil!)} left';
    }
    return 'Urgent';
  }

  String _formatUrgentTimeLeft(DateTime urgentUntil) {
    final diff = urgentUntil.difference(DateTime.now());
    if (diff.isNegative) {
      return '<1m';
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
}

class _ListingTagTone {
  const _ListingTagTone({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;

  Color get border => foreground.withOpacity(0.28);
}

class _IncomingOfferTile extends StatelessWidget {
  const _IncomingOfferTile({
    required this.listing,
    required this.offer,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    required this.onMarkPickedUp,
    required this.onMarkReturned,
    required this.onOpenRequesterProfile,
  });

  final Listing listing;
  final ListingOffer offer;
  final bool busy;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;
  final Future<void> Function() onMarkPickedUp;
  final Future<void> Function() onMarkReturned;
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
              _OfferStatusChip(
                status: offer.status,
                isInUse: offer.pickedUpAt != null,
                isReturned: offer.returnedAt != null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _timeText(offer.createdAt),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (offer.status == OfferStatus.accepted && offer.pickedUpAt != null) ...[
            const SizedBox(height: 6),
            Text(
              _pickedUpText(
                pickedUpAt: offer.pickedUpAt!,
                dueAt: offer.returnDueAt,
                listingType: listing.type,
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (offer.status == OfferStatus.accepted && offer.returnedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Marked returned by lender.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
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
            if (listing.isLend) ...[
              const SizedBox(height: 10),
              if (offer.returnedAt != null)
                Text(
                  'Marked returned.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else if (offer.pickedUpAt == null)
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onMarkPickedUp,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Mark as picked up'),
                )
              else ...[
                _BorrowDurationSummary(
                  pickedUpAt: offer.pickedUpAt!,
                  returnDueAt: offer.returnDueAt,
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: busy ? null : onMarkReturned,
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const Text('Mark returned'),
                ),
              ],
            ],
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

  String _pickedUpText({
    required DateTime pickedUpAt,
    required DateTime? dueAt,
    required ListingType listingType,
  }) {
    final now = DateTime.now();
    final heldDays = now.difference(pickedUpAt).inDays;
    final displayHeldDays = heldDays < 0 ? 1 : heldDays + 1;
    final dueText = dueAt == null ? 'No due date set' : 'Due ${_formatDate(dueAt)}';
    if (listingType == ListingType.borrow) {
      if (dueAt == null) {
        return 'Return date not set yet.';
      }
      final dueDateText = _formatDate(dueAt);
      final dayDelta = _calendarDayDelta(now, dueAt);
      if (dayDelta > 0) {
        return '$dayDelta day${dayDelta == 1 ? '' : 's'} left to return. Return by $dueDateText.';
      }

      final remaining = dueAt.difference(now);
      if (remaining.isNegative) {
        final overdueDays = _calendarDayDelta(dueAt, now);
        if (overdueDays <= 0) {
          return 'Overdue. Return date was $dueDateText.';
        }
        return 'Overdue by $overdueDays day${overdueDays == 1 ? '' : 's'}. Return date was $dueDateText.';
      }
      return '${_formatHoursMinutes(remaining)} left to return. Return by $dueDateText.';
    }
    return 'Borrower has had this for $displayHeldDays day${displayHeldDays == 1 ? '' : 's'}. $dueText';
  }

  int _calendarDayDelta(DateTime from, DateTime to) {
    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = DateTime(to.year, to.month, to.day);
    return toDay.difference(fromDay).inDays;
  }

  String _formatHoursMinutes(Duration remaining) {
    final minutesTotal = remaining.inMinutes <= 0 ? 1 : remaining.inMinutes;
    final hours = minutesTotal ~/ 60;
    final minutes = minutesTotal % 60;
    if (hours <= 0) {
      return '${minutes == 0 ? 1 : minutes}m';
    }
    return '${hours}h ${minutes}m';
  }

  String _formatDate(DateTime date) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _BorrowDurationSummary extends StatelessWidget {
  const _BorrowDurationSummary({
    required this.pickedUpAt,
    required this.returnDueAt,
  });

  final DateTime pickedUpAt;
  final DateTime? returnDueAt;

  @override
  Widget build(BuildContext context) {
    final daysHeld = DateTime.now().difference(pickedUpAt).inDays;
    final displayHeldDays = daysHeld < 0 ? 1 : daysHeld + 1;
    final dueText = returnDueAt == null
        ? 'No due date set'
        : 'Due ${_formatDate(returnDueAt!)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Borrower has had this item for $displayHeldDays day${displayHeldDays == 1 ? '' : 's'}.\n$dueText',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
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
        final phone = UsPhoneInputFormatter.formatForDisplay(
          (user?.phoneNumber ?? '').trim(),
        );

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
  const _OfferStatusChip({
    required this.status,
    this.isInUse = false,
    this.isReturned = false,
  });

  final OfferStatus status;
  final bool isInUse;
  final bool isReturned;

  @override
  Widget build(BuildContext context) {
    if (isReturned) {
      return Chip(
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        label: const Text('Returned'),
      );
    }

    final color = switch (status) {
      OfferStatus.pending => Theme.of(context).colorScheme.secondaryContainer,
      OfferStatus.accepted => Colors.green.shade100,
      OfferStatus.declined => Theme.of(context).colorScheme.errorContainer,
    };

    final label =
        status == OfferStatus.accepted
            ? (isInUse ? 'In Use' : 'Matched')
            : switch (status) {
                OfferStatus.pending => 'Pending',
                OfferStatus.accepted => 'Matched',
                OfferStatus.declined => 'Declined',
              };

    return Chip(
      backgroundColor: color,
      label: Text(label),
    );
  }
}

enum _RelistAction {
  now,
  withEdits,
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
