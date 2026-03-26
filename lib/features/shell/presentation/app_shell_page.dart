import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../home/presentation/home_feed_page.dart';
import '../../listings/presentation/create_listing_sheet.dart';
import '../../my_listings/presentation/my_listings_page.dart';
import '../../offers/presentation/my_offers_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../../providers/auth_controller.dart';
import '../../../shared/widgets/knocknock_logo.dart';

class AppShellPage extends StatefulWidget {
  const AppShellPage({super.key});

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  int _index = 0;
  bool _isCreateSheetOpen = false;

  static const _tabs = [
    HomeFeedPage(),
    MyListingsPage(),
    SizedBox.shrink(),
    MyOffersPage(),
    ProfilePage(),
  ];

  Future<void> _openCreateSheet() async {
    if (_isCreateSheetOpen) {
      return;
    }

    _isCreateSheetOpen = true;
    await showCreateListingSheet(context);
    _isCreateSheetOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(
        title: const _BrandAppBarTitle(),
        actions: [
          IconButton(
            onPressed: auth.isBusy ? null : auth.signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          if (index == 2) {
            _openCreateSheet();
            return;
          }
          setState(() {
            _index = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'My Listings',
          ),
          NavigationDestination(icon: Icon(Icons.add_box_outlined), label: 'Create'),
          NavigationDestination(
            icon: Icon(Icons.local_offer_outlined),
            label: 'My Offers',
          ),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

class _BrandAppBarTitle extends StatelessWidget {
  const _BrandAppBarTitle();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KnocknockLogo(size: 30),
        SizedBox(width: 8),
        KnocknockWordmark(width: 138, height: 34),
      ],
    );
  }
}
