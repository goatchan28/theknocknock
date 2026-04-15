import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../../../models/app_notification.dart';
import '../../../models/listing.dart';
import '../../home/presentation/home_feed_page.dart';
import '../../listings/presentation/create_listing_sheet.dart';
import '../../listings/presentation/create_listing_flow_result.dart';
import '../../listings/presentation/listing_detail_page.dart';
import '../../market/presentation/market_lane_page.dart';
import '../../my_listings/presentation/manage_listing_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../../providers/auth_controller.dart';
import '../../../services/listing_service.dart';
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
  final _lendLaneKey = GlobalKey<MarketLanePageState>();
  final _borrowLaneKey = GlobalKey<MarketLanePageState>();

  late final List<Widget> _tabs = [
    const HomeFeedPage(),
    MarketLanePage(
      key: _lendLaneKey,
      laneType: ListingType.lend,
    ),
    const SizedBox.shrink(),
    MarketLanePage(
      key: _borrowLaneKey,
      laneType: ListingType.borrow,
    ),
    const ProfilePage(),
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
      final listingType = await _resolveListingType(listingId);
      if (listingType == ListingType.borrow) {
        _setTabIndex(3);
        _borrowLaneKey.currentState?.showListingsTab();
      } else {
        _setTabIndex(1);
        _lendLaneKey.currentState?.showListingsTab();
      }
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
    _pushOpenSub = pushService.openIntentStream.listen((intent) {
      unawaited(_handlePushOpenIntent(intent));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = pushService.takePendingOpenIntent();
      if (pending != null && mounted) {
        unawaited(_handlePushOpenIntent(pending));
      }
    });
  }

  @override
  void dispose() {
    _pushOpenSub?.cancel();
    super.dispose();
  }

  Future<void> _handlePushOpenIntent(PushOpenIntent intent) async {
    if (!mounted) {
      return;
    }

    switch (intent.destination) {
      case PushOpenDestination.listings:
        await _openListingsDestination(intent);
        final listingId = intent.listingId?.trim() ?? '';
        if (listingId.isNotEmpty &&
            (intent.type == 'offer_received' ||
                intent.type == 'urgent_no_response')) {
          unawaited(_openManageListing(listingId));
        }
        break;
      case PushOpenDestination.offers:
        await _openOffersDestination(intent);
        break;
      case PushOpenDestination.home:
        _setTabIndex(0);
        final listingId = intent.listingId?.trim() ?? '';
        if (listingId.isNotEmpty && intent.type == 'urgent_borrow_posted') {
          unawaited(_openListingDetail(listingId));
        }
        break;
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
      unawaited(_markMarketplaceNotificationsRead());
      return;
    }
    if (index == 3) {
      unawaited(_markMarketplaceNotificationsRead());
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

  Future<void> _markMarketplaceNotificationsRead() async {
    final userId = context.read<AuthController>().firebaseUser?.uid;
    if (userId == null) {
      return;
    }
    try {
      await context.read<NotificationService>().markUnreadByTypes(
        userId: userId,
        types: const {
          AppNotificationType.offerReceived,
          AppNotificationType.offerAccepted,
          AppNotificationType.offerDeclined,
          AppNotificationType.urgentNoResponse,
          AppNotificationType.returnDueSoonLender,
          AppNotificationType.returnDueSoonBorrower,
        },
      );
    } catch (_) {}
  }

  Future<void> _openListingsDestination(PushOpenIntent intent) async {
    final listingType = await _resolveListingType(intent.listingId);
    if (!mounted) {
      return;
    }
    if (listingType == ListingType.borrow) {
      _setTabIndex(3);
      _borrowLaneKey.currentState?.showListingsTab();
    } else {
      _setTabIndex(1);
      _lendLaneKey.currentState?.showListingsTab();
    }
  }

  Future<void> _openOffersDestination(PushOpenIntent intent) async {
    final listingType = await _resolveListingType(intent.listingId);
    if (!mounted) {
      return;
    }
    final laneForRequester = listingType == ListingType.borrow
        ? ListingType.lend
        : ListingType.borrow;
    if (laneForRequester == ListingType.borrow) {
      _setTabIndex(3);
      _borrowLaneKey.currentState?.showOffersTab();
    } else {
      _setTabIndex(1);
      _lendLaneKey.currentState?.showOffersTab();
    }
  }

  Future<ListingType> _resolveListingType(String? listingId) async {
    final normalized = listingId?.trim() ?? '';
    if (normalized.isEmpty) {
      return ListingType.lend;
    }
    try {
      final listing = await context.read<ListingService>().getListingById(normalized);
      return listing?.type ?? ListingType.lend;
    } catch (_) {
      return ListingType.lend;
    }
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
      return _buildScaffold();
    }

    return StreamBuilder<List<AppNotification>>(
      stream: context.read<NotificationService>().watchMyNotifications(userId),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <AppNotification>[];
        final unreadTotal = items.where((item) => item.isUnread).length;
        _syncAppIconBadgeCount(unreadTotal);
        return _buildScaffold();
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

  Widget _buildScaffold() {
    return Scaffold(
      appBar: AppBar(
        title: _BrandAppBarTitle(
          onTap: () => _setTabIndex(0),
        ),
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
          const NavigationDestination(
            icon: Icon(Icons.handshake_outlined),
            label: 'Lend',
          ),
          const NavigationDestination(
            icon: Icon(Icons.add_box_outlined),
            label: 'Create',
          ),
          const NavigationDestination(
            icon: Icon(Icons.assignment_return_outlined),
            label: 'Borrow',
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
  const _BrandAppBarTitle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KnocknockLogo(size: 30),
            SizedBox(width: 8),
            KnocknockWordmark(width: 138, height: 34),
          ],
        ),
      ),
    );
  }
}
