import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/listing.dart';
import '../../../services/listing_service.dart';
import '../../listings/presentation/listing_detail_page.dart';

class HomeFeedPage extends StatefulWidget {
  const HomeFeedPage({super.key});

  @override
  State<HomeFeedPage> createState() => _HomeFeedPageState();
}

class _HomeFeedPageState extends State<HomeFeedPage> {
  static const _categorySuggestions = <String>[
    'Dorm Essentials',
    'Outdoors',
    'Sports',
    'Kitchen',
    'Clothing',
    'Electronics',
    'School Supplies',
    'Other',
  ];

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Stream<List<Listing>>? _activeListingsStream;

  final Set<ListingType> _selectedTypes = {
    ListingType.lend,
    ListingType.borrow,
  };
  final Set<String> _selectedCategories = <String>{};
  String _search = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _activeListingsStream ??=
        context.read<ListingService>().watchActiveListings();
  }

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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Listing>>(
      stream: _activeListingsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final listings = snapshot.data ?? const <Listing>[];
        final categories = _buildCategoryOptions(listings);
        final filtered = _applyFilters(listings);

        final borrowListings = filtered.where((l) => l.isBorrow).toList();
        final lendListings = filtered.where((l) => l.isLend).toList();
        final borrowOnlyView =
            _selectedTypes.length == 1 && _selectedTypes.contains(ListingType.borrow);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSearchAndFilterBar(categories),
            const SizedBox(height: 16),
            if (listings.isEmpty)
              const _EmptyFeedCard()
            else ...[
              if (_selectedTypes.contains(ListingType.borrow))
                _BorrowSection(
                  listings: borrowListings,
                  asGrid: borrowOnlyView,
                ),
              if (_selectedTypes.contains(ListingType.borrow) &&
                  _selectedTypes.contains(ListingType.lend))
                const SizedBox(height: 20),
              if (_selectedTypes.contains(ListingType.lend))
                _LendSection(listings: lendListings),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(
                    child: Text('No listings match this search/filter yet.'),
                  ),
                ),
            ],
          ],
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

      final matchesCategory = _selectedCategories.isEmpty ||
          _selectedCategories.contains(listing.category);

      return matchesSearch && matchesType && matchesCategory;
    }).toList();
  }

  Set<String> _buildCategoryOptions(List<Listing> listings) {
    final set = <String>{..._categorySuggestions};
    for (final listing in listings) {
      if (listing.category.trim().isNotEmpty) {
        set.add(listing.category.trim());
      }
    }
    return set;
  }

  Widget _buildSearchAndFilterBar(Set<String> categories) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search items',
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
          onPressed: () => _openFilterSheet(categories),
          icon: const Icon(Icons.tune),
          label: const Text('Filter'),
        ),
      ],
    );
  }

  Widget _buildSearchCategorySuggestions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _categorySuggestions.map((category) {
        final selected = _selectedCategories.contains(category);
        return FilterChip(
          label: Text(category),
          selected: selected,
          onSelected: (value) {
            setState(() {
              if (value) {
                _selectedCategories.add(category);
              } else {
                _selectedCategories.remove(category);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Future<void> _openFilterSheet(Set<String> categories) async {
    final result = await showModalBottomSheet<_FeedFilterResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final tempTypes = <ListingType>{..._selectedTypes};
        final tempCategories = <String>{..._selectedCategories};

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
                    Text(
                      'Type',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    CheckboxListTile(
                      value: tempTypes.contains(ListingType.lend),
                      onChanged: (value) => toggleType(ListingType.lend, value ?? false),
                      title: const Text('Lend'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      value: tempTypes.contains(ListingType.borrow),
                      onChanged:
                          (value) => toggleType(ListingType.borrow, value ?? false),
                      title: const Text('Borrow'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Categories',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 220,
                      child: ListView(
                        children: categories.map((category) {
                          final selected = tempCategories.contains(category);
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (value) {
                              setSheetState(() {
                                if (value == true) {
                                  tempCategories.add(category);
                                } else {
                                  tempCategories.remove(category);
                                }
                              });
                            },
                            title: Text(category),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).pop(
                                const _FeedFilterResult(
                                  selectedTypes: {
                                    ListingType.lend,
                                    ListingType.borrow,
                                  },
                                  selectedCategories: <String>{},
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
                                _FeedFilterResult(
                                  selectedTypes: tempTypes,
                                  selectedCategories: tempCategories,
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
        ..addAll(result.selectedTypes);
      _selectedCategories
        ..clear()
        ..addAll(result.selectedCategories);
    });
  }

}

class _BorrowSection extends StatelessWidget {
  const _BorrowSection({
    required this.listings,
    required this.asGrid,
  });

  final List<Listing> listings;
  final bool asGrid;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Borrow requests', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (listings.isEmpty) const Text('No borrow requests match your filters.') else if (asGrid)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: listings.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (context, index) {
              return _ListingTileCard(listing: listings[index]);
            },
          )
        else
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: listings.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final listing = listings[index];
                return SizedBox(
                  width: 220,
                  child: _ListingTileCard(
                    listing: listing,
                    compact: true,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _LendSection extends StatelessWidget {
  const _LendSection({required this.listings});

  final List<Listing> listings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lend listings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (listings.isEmpty)
          const Text('No lend listings match your filters.')
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: listings.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (context, index) {
              return _ListingTileCard(listing: listings[index]);
            },
          ),
      ],
    );
  }
}

class _ListingTileCard extends StatelessWidget {
  const _ListingTileCard({
    required this.listing,
    this.compact = false,
  });

  final Listing listing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final urgentTone = _urgentTone(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ListingDetailPage(listingId: listing.id),
          ),
        );
      },
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                child: _ListingImage(imageUrl: listing.imageUrl),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.title,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    listing.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (listing.isBorrow && listing.isUrgent)
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
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTimeAgo(listing.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _ChipTone _urgentTone(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ChipTone(
      background: scheme.errorContainer,
      foreground: scheme.onErrorContainer,
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
        color: Theme.of(context).colorScheme.surfaceVariant,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_outlined),
      );
    }

    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      width: double.infinity,
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

String _formatTimeAgo(DateTime? dateTime) {
  if (dateTime == null) {
    return 'Posted recently';
  }

  final now = DateTime.now();
  final diff = now.difference(dateTime);

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

class _FeedFilterResult {
  const _FeedFilterResult({
    required this.selectedTypes,
    required this.selectedCategories,
  });

  final Set<ListingType> selectedTypes;
  final Set<String> selectedCategories;
}

class _EmptyFeedCard extends StatelessWidget {
  const _EmptyFeedCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No listings yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'No listings yet. Be the first to post one.',
          ),
        ],
      ),
    );
  }
}
