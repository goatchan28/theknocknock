import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/listing.dart';
import '../../../models/listing_offer.dart';
import '../../../models/public_profile.dart';
import '../../../providers/auth_controller.dart';
import '../../../services/listing_service.dart';
import '../../../services/public_profile_service.dart';
import '../../listings/presentation/listing_detail_page.dart';

class MyOffersPage extends StatefulWidget {
  const MyOffersPage({
    super.key,
    this.listingTypeFilter,
  });

  final ListingType? listingTypeFilter;

  @override
  State<MyOffersPage> createState() => _MyOffersPageState();
}

class _MyOffersPageState extends State<MyOffersPage> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Stream<List<ListingOffer>>? _myOffersStream;
  String? _streamRequesterId;
  final Set<_OfferFilterStatus> _selectedStatuses = {
    ..._OfferFilterStatus.values,
  };

  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _applySearch([String? value]) {
    final normalized = (value ?? _searchController.text).trim().toLowerCase();
    if (!mounted || normalized == _search) {
      return;
    }
    setState(() {
      _search = normalized;
    });
  }

  void _applySearchLive(String value) {
    final normalized = value.trim().toLowerCase();
    if (!mounted || normalized == _search) {
      return;
    }

    final keepFocus = _searchFocusNode.hasFocus;
    setState(() {
      _search = normalized;
    });

    if (keepFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (!_searchFocusNode.hasFocus) {
          _searchFocusNode.requestFocus();
          _searchController.selection = TextSelection.collapsed(
            offset: _searchController.text.length,
          );
        }
      });
    }
  }

  void _clearSearch() {
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();

    if (_searchController.text.isEmpty && _search.isEmpty) {
      return;
    }
    _searchController.clear();
    setState(() {
      _search = '';
    });
  }

  void _ensureStream(String requesterId) {
    if (_streamRequesterId == requesterId && _myOffersStream != null) {
      return;
    }
    _streamRequesterId = requesterId;
    _myOffersStream = context.read<ListingService>().watchMyOffers(requesterId);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final requesterId = auth.firebaseUser?.uid;

    if (requesterId == null) {
      return const Center(child: Text('Please sign in again.'));
    }
    _ensureStream(requesterId);

    return StreamBuilder<List<ListingOffer>>(
      stream: _myOffersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final offers = snapshot.data ?? const <ListingOffer>[];
        final visibleOffers = offers
            .where(_matchesListingTypeFilter)
            .where((offer) => _selectedStatuses.contains(_filterStatusForOffer(offer)))
            .where(_matchesSearch)
            .toList();

        return _buildOffersList(
          allOffers: offers,
          visibleOffers: visibleOffers,
        );
      },
    );
  }

  Widget _buildOffersList({
    required List<ListingOffer> allOffers,
    required List<ListingOffer> visibleOffers,
  }) {
    final showStatusChip =
        _selectedStatuses.length != _OfferFilterStatus.values.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSearchAndFilterBar(),
        if (showStatusChip) ...[
          const SizedBox(height: 10),
          _buildActiveFilterChip(),
        ],
        const SizedBox(height: 16),
        if (allOffers.isEmpty)
          const _EmptyState(
            message: 'No offers yet. Browse listings and tap Make offer.',
          )
        else if (visibleOffers.isEmpty)
          const _EmptyState(
            message: 'No offers match your search/filter.',
          )
        else
          ...visibleOffers.map(
            (offer) => _OfferRow(offer: offer),
          ),
      ],
    );
  }

  bool _matchesSearch(ListingOffer offer) {
    final normalized = _search.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    final title = offer.listingTitle.trim().toLowerCase();
    if (title.startsWith(normalized)) {
      return true;
    }
    final words = title.split(RegExp(r'\s+'));
    return words.any((word) => word.startsWith(normalized));
  }

  bool _matchesListingTypeFilter(ListingOffer offer) {
    final filter = widget.listingTypeFilter;
    if (filter == null) {
      return true;
    }
    return offer.listingType == filter;
  }

  Widget _buildSearchAndFilterBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search offer by item name',
              suffixIcon: IconButton(
                tooltip: 'Clear',
                onPressed: _clearSearch,
                icon: const Icon(Icons.clear),
              ),
            ),
            onChanged: _applySearchLive,
            onSubmitted: _applySearch,
            onTapOutside: (_) => _searchFocusNode.unfocus(),
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
    final label = 'Status: ${_selectedStatuses.map(_statusLabel).join(', ')}';

    return Chip(label: Text(label));
  }

  Future<void> _openStatusFilterSheet() async {
    final result = await showModalBottomSheet<Set<_OfferFilterStatus>>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final tempStatuses = <_OfferFilterStatus>{..._selectedStatuses};

        return StatefulBuilder(
          builder: (context, setSheetState) {
            void toggleStatus(_OfferFilterStatus status, bool selected) {
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
                    ..._OfferFilterStatus.values.map(
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
                              Navigator.of(context).pop(_OfferFilterStatus.values.toSet());
                            },
                            child: const Text('Reset'),
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

  _OfferFilterStatus _filterStatusForOffer(ListingOffer offer) {
    switch (offer.status) {
      case OfferStatus.pending:
        return _OfferFilterStatus.pending;
      case OfferStatus.declined:
        return _OfferFilterStatus.declined;
      case OfferStatus.accepted:
        if (offer.returnedAt != null) {
          return _OfferFilterStatus.returned;
        }
        if (offer.pickedUpAt != null) {
          return _OfferFilterStatus.inUse;
        }
        return _OfferFilterStatus.matched;
    }
  }

  String _statusLabel(_OfferFilterStatus status) {
    switch (status) {
      case _OfferFilterStatus.pending:
        return 'Pending';
      case _OfferFilterStatus.matched:
        return 'Matched';
      case _OfferFilterStatus.inUse:
        return 'In Use';
      case _OfferFilterStatus.declined:
        return 'Declined';
      case _OfferFilterStatus.returned:
        return 'Returned';
    }
  }

}

enum _OfferFilterStatus {
  pending,
  matched,
  inUse,
  declined,
  returned,
}

class _OfferRow extends StatefulWidget {
  const _OfferRow({
    required this.offer,
  });

  final ListingOffer offer;

  @override
  State<_OfferRow> createState() => _OfferRowState();
}

class _OfferRowState extends State<_OfferRow> {
  Stream<Listing?>? _listingStream;
  String? _listingId;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureListingStream();
  }

  @override
  void didUpdateWidget(covariant _OfferRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offer.listingId != widget.offer.listingId) {
      _ensureListingStream();
    }
  }

  void _ensureListingStream() {
    final listingId = widget.offer.listingId;
    if (_listingId == listingId && _listingStream != null) {
      return;
    }
    _listingId = listingId;
    _listingStream = context.read<ListingService>().watchListing(listingId);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Listing?>(
      stream: _listingStream,
      builder: (context, listingSnapshot) {
        final listing = listingSnapshot.data;
        final title = listing?.title.trim().isNotEmpty == true
            ? listing!.title
            : (widget.offer.listingTitle.trim().isNotEmpty
                ? widget.offer.listingTitle.trim()
                : 'Listing unavailable');
        final isReturned = widget.offer.status == OfferStatus.accepted &&
            listing?.returnedFromMatch == true;
        final isInUse = widget.offer.pickedUpAt != null && !isReturned;
        final currentUserId = context.read<AuthController>().firebaseUser?.uid;
        final listingType = listing?.type ?? widget.offer.listingType;
        final borrowerId =
            listingType == ListingType.borrow ? widget.offer.ownerId : widget.offer.requesterId;
        final isCurrentUserBorrower =
            currentUserId != null && currentUserId == borrowerId;
        final isLenderManagingBorrowFlow =
            widget.offer.status == OfferStatus.accepted &&
            listing?.type == ListingType.borrow &&
            widget.offer.returnedAt == null;
        final hasPickedUp = widget.offer.pickedUpAt != null;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ListingDetailPage(listingId: widget.offer.listingId),
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 70,
                          height: 70,
                          child: _OfferThumb(imageUrl: listing?.imageUrl),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              listing?.category ?? 'Unknown category',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _StatusChip(
                                  status: widget.offer.status,
                                  isReturned: isReturned,
                                  isInUse: isInUse,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _CounterpartyName(userId: widget.offer.ownerId),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  if (isInUse &&
                      widget.offer.pickedUpAt != null &&
                      !(isLenderManagingBorrowFlow && hasPickedUp)) ...[
                    const SizedBox(height: 8),
                    Text(
                      _inUseSummaryText(
                        pickedUpAt: widget.offer.pickedUpAt!,
                        returnDueAt: widget.offer.returnDueAt,
                        isBorrowerView: isCurrentUserBorrower,
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 6),
                  if (widget.offer.status == OfferStatus.pending) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _cancelPendingRequest,
                      icon: const Icon(Icons.close),
                      label: const Text('Cancel request'),
                    ),
                  ] else if (isLenderManagingBorrowFlow && !hasPickedUp) ...[
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: _busy || listing == null
                          ? null
                          : () => _markAsPickedUp(listing),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Mark as picked up'),
                    ),
                  ] else if (isLenderManagingBorrowFlow && hasPickedUp) ...[
                    const SizedBox(height: 10),
                    _BorrowDurationInfo(
                      pickedUpAt: widget.offer.pickedUpAt!,
                      returnDueAt: widget.offer.returnDueAt,
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed:
                          _busy ? null : () => _markAsReturned(widget.offer.id),
                      icon: const Icon(Icons.assignment_return_outlined),
                      label: const Text('Mark returned'),
                    ),
                  ] else if (isReturned) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Item marked returned by lender.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _cancelPendingRequest() async {
    final requesterId = context.read<AuthController>().firebaseUser?.uid;
    if (requesterId == null) {
      _showMessage('Session expired. Please sign in again.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: const Text(
          'This removes your pending request from both sides.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel request'),
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
      await context.read<ListingService>().cancelPendingOffer(
            offerId: widget.offer.id,
            requesterId: requesterId,
          );
      if (!mounted) {
        return;
      }
      _showMessage('Request cancelled.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not cancel request: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _markAsPickedUp(Listing listing) async {
    final requesterId = context.read<AuthController>().firebaseUser?.uid;
    if (requesterId == null) {
      _showMessage('Session expired. Please sign in again.');
      return;
    }

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'When should ${listing.ownerDisplayName.split(' ').first} return it?',
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
            offerId: widget.offer.id,
            actorId: requesterId,
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

  Future<void> _markAsReturned(String offerId) async {
    final requesterId = context.read<AuthController>().firebaseUser?.uid;
    if (requesterId == null) {
      _showMessage('Session expired. Please sign in again.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark item as returned?'),
        content: const Text(
          'This closes the active borrow match. You can no longer manage this item from offers.',
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
            offerId: offerId,
            actorId: requesterId,
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

  String _inUseSummaryText({
    required DateTime pickedUpAt,
    required DateTime? returnDueAt,
    required bool isBorrowerView,
  }) {
    final now = DateTime.now();
    final daysHeld = now.difference(pickedUpAt).inDays;
    final displayHeldDays = daysHeld < 0 ? 1 : daysHeld + 1;
    final dueText = returnDueAt == null ? 'No return date set' : _formatDate(returnDueAt);
    if (isBorrowerView) {
      if (returnDueAt == null) {
        return 'Return date not set yet.';
      }
      final dayDelta = _calendarDayDelta(now, returnDueAt);
      if (dayDelta > 0) {
        return '$dayDelta day${dayDelta == 1 ? '' : 's'} left to return. Return by $dueText.';
      }

      final remaining = returnDueAt.difference(now);
      if (remaining.isNegative) {
        final overdueDays = _calendarDayDelta(returnDueAt, now);
        if (overdueDays <= 0) {
          return 'Overdue. Return date was $dueText.';
        }
        return 'Overdue by $overdueDays day${overdueDays == 1 ? '' : 's'}. Return date was $dueText.';
      }
      return '${_formatHoursMinutes(remaining)} left to return. Return by $dueText.';
    }
    return 'Lent for $displayHeldDays day${displayHeldDays == 1 ? '' : 's'}. ${returnDueAt == null ? dueText : 'Due $dueText'}.';
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    this.isReturned = false,
    this.isInUse = false,
  });

  final OfferStatus status;
  final bool isReturned;
  final bool isInUse;

  @override
  Widget build(BuildContext context) {
    if (isReturned) {
      return Chip(
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        label: const Text('Returned'),
      );
    }

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
          OfferStatus.accepted => isInUse ? 'In Use' : 'Matched',
          OfferStatus.declined => 'Declined',
        },
      ),
    );
  }
}

class _BorrowDurationInfo extends StatelessWidget {
  const _BorrowDurationInfo({
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

  static String _formatDate(DateTime date) {
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

class _ChipTone {
  const _ChipTone({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;

  Color get border => foreground.withOpacity(0.28);
}

class _OfferThumb extends StatelessWidget {
  const _OfferThumb({required this.imageUrl});

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

class _CounterpartyName extends StatelessWidget {
  const _CounterpartyName({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final profileService = context.read<PublicProfileService>();
    return StreamBuilder<PublicProfile?>(
      stream: profileService.watchPublicProfile(userId),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final displayName = (profile?.displayName ?? '').trim().isNotEmpty
            ? profile!.displayName.trim()
            : _shortUser(userId);
        return Text(
          'With $displayName',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        );
      },
    );
  }

  String _shortUser(String uid) {
    if (uid.length <= 8) {
      return uid;
    }
    return '${uid.substring(0, 8)}...';
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
