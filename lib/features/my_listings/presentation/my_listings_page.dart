import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/listing.dart';
import '../../../providers/auth_controller.dart';
import '../../../services/listing_service.dart';
import '../../listings/presentation/create_listing_flow_result.dart';
import '../../listings/presentation/create_listing_sheet.dart';
import '../../listings/presentation/listing_detail_page.dart';
import 'manage_listing_page.dart';

class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});

  @override
  State<MyListingsPage> createState() => _MyListingsPageState();
}

class _MyListingsPageState extends State<MyListingsPage> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Stream<List<Listing>>? _ownerListingsStream;
  Stream<Map<String, int>>? _offerCountsStream;
  String? _streamsUid;

  final Set<ListingType> _selectedTypes = {
    ListingType.lend,
    ListingType.borrow,
  };

  final Set<_ActivityFilter> _selectedActivity = {
    _ActivityFilter.active,
    _ActivityFilter.inactive,
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

  void _ensureStreams(String uid) {
    if (_streamsUid == uid &&
        _ownerListingsStream != null &&
        _offerCountsStream != null) {
      return;
    }
    final listingService = context.read<ListingService>();
    _streamsUid = uid;
    _ownerListingsStream = listingService.watchOwnerListings(uid);
    _offerCountsStream = listingService.watchOfferCountsForOwner(uid);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final uid = auth.firebaseUser?.uid;

    if (uid == null) {
      return const Center(child: Text('Please sign in again.'));
    }
    _ensureStreams(uid);

    return StreamBuilder<List<Listing>>(
      stream: _ownerListingsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final listings = snapshot.data ?? const <Listing>[];
        final baseFiltered = _applyFilters(listings);

        return StreamBuilder<Map<String, int>>(
          stream: _offerCountsStream,
          builder: (context, offerSnapshot) {
            final offerCounts = offerSnapshot.data ?? const <String, int>{};
            final filtered = _sortByOfferPriority(baseFiltered, offerCounts);

            return Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSearchAndFilterBar(),
                  const SizedBox(height: 10),
                  const SizedBox(height: 6),
                  if (listings.isEmpty)
                    const _EmptyState(
                      message: 'You have not posted any listings yet.',
                    )
                  else if (filtered.isEmpty)
                    const _EmptyState(
                      message: 'No listings match your search/filter.',
                    )
                  else
                    ...filtered.map((listing) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ListingRow(
                          listing: listing,
                          offerCount: offerCounts[listing.id] ?? 0,
                          onToggleArchive: () => _toggleArchive(listing),
                          onTap: () => _openManagePage(listing),
                        ),
                      );
                    }),
                  const SizedBox(height: 80),
                ],
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () async {
                  final result = await showCreateListingSheet(context);
                  if (!context.mounted || result == null) {
                    return;
                  }
                  if (result.action == CreateListingNextAction.viewListing) {
                    final listingId = result.listingId?.trim() ?? '';
                    if (listingId.isEmpty) {
                      return;
                    }
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ListingDetailPage(listingId: listingId),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Post'),
              ),
            );
          },
        );
      },
    );
  }

  List<Listing> _applyFilters(List<Listing> input) {
    return input.where((listing) {
      final normalizedSearch = _search.trim().toLowerCase();
      final matchesSearch = normalizedSearch.isEmpty ||
          listing.title.toLowerCase().contains(normalizedSearch);

      final matchesType = _selectedTypes.contains(listing.type);

      final isInactive = listing.status != ListingStatus.active;
      final matchesActivity = (listing.status == ListingStatus.active &&
              _selectedActivity.contains(_ActivityFilter.active)) ||
          (isInactive && _selectedActivity.contains(_ActivityFilter.inactive));

      return matchesSearch && matchesType && matchesActivity;
    }).toList();
  }

  List<Listing> _sortByOfferPriority(
    List<Listing> input,
    Map<String, int> offerCounts,
  ) {
    final output = <Listing>[...input];
    output.sort((a, b) {
      final aHasOffers = (offerCounts[a.id] ?? 0) > 0;
      final bHasOffers = (offerCounts[b.id] ?? 0) > 0;
      if (aHasOffers != bHasOffers) {
        return aHasOffers ? -1 : 1;
      }

      final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
      final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });
    return output;
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
              hintText: 'Search your listings',
              suffixIcon: IconButton(
                tooltip: 'Clear',
                onPressed: _clearSearch,
                icon: const Icon(Icons.clear),
              ),
            ),
            onChanged: _applySearchLive,
            onSubmitted: _applySearch,
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.tonalIcon(
          onPressed: _openFilterSheet,
          icon: const Icon(Icons.tune),
          label: const Text('Filter'),
        ),
      ],
    );
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_MyFilterResult>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final tempTypes = <ListingType>{..._selectedTypes};
        final tempActivity = <_ActivityFilter>{..._selectedActivity};

        return StatefulBuilder(
          builder: (context, setSheetState) {
            void toggleType(ListingType type, bool selected) {
              setSheetState(() {
                if (selected) {
                  tempTypes.add(type);
                } else if (tempTypes.length > 1) {
                  tempTypes.remove(type);
                }
              });
            }

            void toggleActivity(_ActivityFilter value, bool selected) {
              setSheetState(() {
                if (selected) {
                  tempActivity.add(value);
                } else if (tempActivity.length > 1) {
                  tempActivity.remove(value);
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
                      'Filters',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text('Type', style: Theme.of(context).textTheme.titleMedium),
                    CheckboxListTile(
                      value: tempTypes.contains(ListingType.lend),
                      onChanged: (value) => toggleType(ListingType.lend, value ?? false),
                      title: const Text('Lend'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      value: tempTypes.contains(ListingType.borrow),
                      onChanged: (value) => toggleType(ListingType.borrow, value ?? false),
                      title: const Text('Borrow'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 8),
                    Text('Status', style: Theme.of(context).textTheme.titleMedium),
                    CheckboxListTile(
                      value: tempActivity.contains(_ActivityFilter.active),
                      onChanged: (value) =>
                          toggleActivity(_ActivityFilter.active, value ?? false),
                      title: const Text('Active'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      value: tempActivity.contains(_ActivityFilter.inactive),
                      onChanged: (value) =>
                          toggleActivity(_ActivityFilter.inactive, value ?? false),
                      title: const Text('Inactive (Archived/In Use)'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).pop(
                                const _MyFilterResult(
                                  types: {ListingType.lend, ListingType.borrow},
                                  activity: {
                                    _ActivityFilter.active,
                                    _ActivityFilter.inactive,
                                  },
                                ),
                              );
                            },
                            child: const Text('Clear'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              Navigator.of(context).pop(
                                _MyFilterResult(
                                  types: tempTypes,
                                  activity: tempActivity,
                                ),
                              );
                            },
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
      _selectedTypes
        ..clear()
        ..addAll(result.types);

      _selectedActivity
        ..clear()
        ..addAll(result.activity);
    });
  }

  Future<void> _toggleArchive(Listing listing) async {
    final uid = context.read<AuthController>().firebaseUser?.uid;
    if (uid == null) {
      _showMessage('Please sign in again.');
      return;
    }

    final shouldArchive = listing.status != ListingStatus.archived;
    final reopeningToSold =
        listing.status == ListingStatus.archived &&
            (listing.hasAcceptedMatch || listing.archivedFromSold);

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
                ? 'Listing unarchived to in use.'
                : 'Listing unarchived.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not update listing: $error');
    }
  }

  void _openManagePage(Listing listing) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManageListingPage(listingId: listing.id),
      ),
    );
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ListingRow extends StatelessWidget {
  const _ListingRow({
    required this.listing,
    required this.offerCount,
    required this.onToggleArchive,
    required this.onTap,
  });

  final Listing listing;
  final int offerCount;
  final Future<void> Function() onToggleArchive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typeTone = _typeTone(context, listing.type);
    final statusTone = _statusTone(context, listing.status);

    return Dismissible(
      key: ValueKey('my_${listing.id}'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      confirmDismiss: (_) async {
        await onToggleArchive();
        return false;
      },
      secondaryBackground: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(listing.status == ListingStatus.archived ? 'Unarchive' : 'Archive'),
            const SizedBox(width: 8),
            const Icon(Icons.archive_outlined),
          ],
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 70,
                      height: 70,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            Chip(
                              label:
                                  Text(listing.type == ListingType.lend ? 'Lend' : 'Borrow'),
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
                          ],
                        ),
                        if (listing.status == ListingStatus.archived) ...[
                          const SizedBox(height: 4),
                          Text(
                            (listing.hasAcceptedMatch || listing.archivedFromSold)
                                ? 'Swipe left to unarchive to in use'
                                : 'Swipe left to unarchive',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right),
                ],
              ),
              if (offerCount > 0)
                Positioned(
                  top: 2,
                  right: 2,
                  child: _OfferCountBadge(count: offerCount),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _statusLabel(ListingStatus status) {
    switch (status) {
      case ListingStatus.active:
        return 'Active';
      case ListingStatus.archived:
        return 'Archived';
      case ListingStatus.sold:
        return 'In Use';
    }
  }

  static _ChipTone _typeTone(BuildContext context, ListingType type) {
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

  static _ChipTone _statusTone(BuildContext context, ListingStatus status) {
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

class _OfferCountBadge extends StatelessWidget {
  const _OfferCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onError,
              fontWeight: FontWeight.w700,
            ),
      ),
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

enum _ActivityFilter { active, inactive }

class _MyFilterResult {
  const _MyFilterResult({
    required this.types,
    required this.activity,
  });

  final Set<ListingType> types;
  final Set<_ActivityFilter> activity;
}
