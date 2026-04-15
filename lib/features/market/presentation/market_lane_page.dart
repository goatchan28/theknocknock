import 'package:flutter/material.dart';

import '../../../models/listing.dart';
import '../../my_listings/presentation/my_listings_page.dart';
import '../../offers/presentation/my_offers_page.dart';

class MarketLanePage extends StatefulWidget {
  const MarketLanePage({
    super.key,
    required this.laneType,
  });

  final ListingType laneType;

  @override
  State<MarketLanePage> createState() => MarketLanePageState();
}

class MarketLanePageState extends State<MarketLanePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  void showListingsTab() {
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
    }
  }

  void showOffersTab() {
    if (_tabController.index != 1) {
      _tabController.animateTo(1);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Listings'),
              Tab(text: 'Requests'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              MyListingsPage(
                fixedType: widget.laneType,
                embedded: true,
                showPostButton: false,
              ),
              MyOffersPage(
                listingTypeFilter: widget.laneType == ListingType.lend
                    ? ListingType.borrow
                    : ListingType.lend,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
