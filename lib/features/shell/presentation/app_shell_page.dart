import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../../../models/app_notification.dart';
import '../../home/presentation/home_feed_page.dart';
import '../../listings/presentation/create_listing_sheet.dart';
import '../../listings/presentation/create_listing_flow_result.dart';
import '../../listings/presentation/listing_detail_page.dart';
import '../../my_listings/presentation/my_listings_page.dart';
import '../../my_listings/presentation/manage_listing_page.dart';
import '../../offers/presentation/my_offers_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../../providers/auth_controller.dart';
import '../../../services/notification_service.dart';
import '../../../services/push_notification_service.dart';
import '../../../shared/widgets/knocknock_logo.dart';

class AppShellPage extends StatefulWidget {
  const AppShellPage({super.key});

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  int _index = 0;
  bool _isCreateSheetOpen = false;
  StreamSubscription<PushOpenIntent>? _pushOpenSub;
  int? _lastAppIconBadgeCount;

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
    final result = await showCreateListingSheet(context);
    _isCreateSheetOpen = false;

    if (!mounted || result == null) {
      return;
    }

    if (result.action == CreateListingNextAction.viewListing) {
      final listingId = result.listingId?.trim() ?? '';
      _setTabIndex(1);
      if (listingId.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (!mounted) {
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ListingDetailPage(listingId: listingId),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final pushService = context.read<PushNotificationService>();
    _pushOpenSub = pushService.openIntentStream.listen(_handlePushOpenIntent);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = pushService.takePendingOpenIntent();
      if (pending != null && mounted) {
        _handlePushOpenIntent(pending);
      }
    });
  }

  @override
  void dispose() {
    _pushOpenSub?.cancel();
    super.dispose();
  }

  void _handlePushOpenIntent(PushOpenIntent intent) {
    if (!mounted) {
      return;
    }

    switch (intent.destination) {
      case PushOpenDestination.listings:
        _setTabIndex(1);
        final listingId = intent.listingId?.trim() ?? '';
        if (listingId.isNotEmpty && intent.type == 'offer_received') {
          _openManageListing(listingId);
        }
      case PushOpenDestination.offers:
        _setTabIndex(3);
      case PushOpenDestination.home:
        _setTabIndex(0);
        final listingId = intent.listingId?.trim() ?? '';
        if (listingId.isNotEmpty && intent.type == 'urgent_borrow_posted') {
          _openListingDetail(listingId);
        }
    }
  }

  void _setTabIndex(int index) {
    if (!mounted) {
      return;
    }
    _markNotificationsForTab(index);
    if (_index == index) {
      return;
    }
    setState(() {
      _index = index;
    });
  }

  void _markNotificationsForTab(int index) {
    if (index == 0) {
      unawaited(_markHomeNotificationsRead());
      return;
    }
    if (index == 1) {
      unawaited(_markListingsNotificationsRead());
      return;
    }
    if (index == 3) {
      unawaited(_markOffersNotificationsRead());
    }
  }

  Future<void> _markHomeNotificationsRead() async {
    final userId = context.read<AuthController>().firebaseUser?.uid;
    if (userId == null) {
      return;
    }
    try {
      await context.read<NotificationService>().markUnreadByTypes(
        userId: userId,
        types: const {AppNotificationType.urgentBorrowPosted},
      );
    } catch (_) {}
  }

  Future<void> _markListingsNotificationsRead() async {
    final userId = context.read<AuthController>().firebaseUser?.uid;
    if (userId == null) {
      return;
    }
    try {
      await context.read<NotificationService>().markUnreadByTypes(
        userId: userId,
        types: const {AppNotificationType.offerReceived},
      );
    } catch (_) {}
  }

  Future<void> _markOffersNotificationsRead() async {
    final userId = context.read<AuthController>().firebaseUser?.uid;
    if (userId == null) {
      return;
    }
    try {
      await context.read<NotificationService>().markUnreadByTypes(
        userId: userId,
        types: const {
          AppNotificationType.offerAccepted,
          AppNotificationType.offerDeclined,
        },
      );
    } catch (_) {}
  }

  Future<void> _openManageListing(String listingId) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManageListingPage(listingId: listingId),
      ),
    );
  }

  Future<void> _openListingDetail(String listingId) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListingDetailPage(listingId: listingId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final userId = auth.firebaseUser?.uid;

    if (userId == null) {
      _syncAppIconBadgeCount(0);
      return _buildScaffold(
        unreadListings: 0,
        unreadOffers: 0,
      );
    }

    return StreamBuilder<List<AppNotification>>(
      stream: context.read<NotificationService>().watchMyNotifications(userId),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <AppNotification>[];
        final unreadTotal = items.where((item) => item.isUnread).length;
        final unreadListings = items
            .where(
              (item) =>
                  item.isUnread && item.type == AppNotificationType.offerReceived,
            )
            .length;
        final unreadOffers = items
            .where(
              (item) =>
                  item.isUnread &&
                  (item.type == AppNotificationType.offerAccepted ||
                      item.type == AppNotificationType.offerDeclined),
            )
            .length;

        _syncAppIconBadgeCount(unreadTotal);
        return _buildScaffold(
          unreadListings: unreadListings,
          unreadOffers: unreadOffers,
        );
      },
    );
  }

  void _syncAppIconBadgeCount(int count) {
    if (_lastAppIconBadgeCount == count) {
      return;
    }
    _lastAppIconBadgeCount = count;
    unawaited(
      context.read<PushNotificationService>().setAppIconBadgeCount(count),
    );
  }

  Widget _buildScaffold({
    required int unreadListings,
    required int unreadOffers,
  }) {
    return Scaffold(
      appBar: AppBar(
        title: const _BrandAppBarTitle(),
      ),
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          if (index == 2) {
            _openCreateSheet();
            return;
          }
          _markNotificationsForTab(index);
          if (_index == index) {
            return;
          }
          setState(() {
            _index = index;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unreadListings > 0,
              label: Text(unreadListings > 99 ? '99+' : '$unreadListings'),
              child: const Icon(Icons.inventory_2_outlined),
            ),
            label: 'Listings',
          ),
          const NavigationDestination(
            icon: Icon(Icons.add_box_outlined),
            label: 'Create',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unreadOffers > 0,
              label: Text(unreadOffers > 99 ? '99+' : '$unreadOffers'),
              child: const Icon(Icons.local_offer_outlined),
            ),
            label: 'Offers',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
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
