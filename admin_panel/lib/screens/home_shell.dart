import 'package:flutter/material.dart';

import '../providers/auth_provider.dart';
import '../widgets/app_scaffold.dart';
import 'bookings_screen.dart';
import 'cases_screen.dart';
import 'chats_screen.dart';
import 'dashboard_screen.dart';
import 'categories_screen.dart';
import 'lawyers_screen.dart';
import 'lawyer_workspace_screen.dart';
import 'notifications_screen.dart';
import 'plans_screen.dart';
import 'reviews_screen.dart';
import 'subscriptions_screen.dart';
import 'users_screen.dart';

/// The internal panel shell. Admin/owner accounts get the existing management
/// navigation; lawyers get a separate read-only workspace and no admin pages.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final List<NavItem> _items;
  late final String _workspaceSubtitle;
  NavItem? _current;

  @override
  void initState() {
    super.initState();
    final role = AuthProvider.of(context).session?.role;
    if (role == 'lawyer') {
      _workspaceSubtitle = 'Lawyer Workspace';
      _items = [
        NavItem(
          title: 'Overview',
          icon: Icons.dashboard_outlined,
          screen: LawyerOverviewScreen(onNavigate: _selectByTitle),
        ),
        NavItem(
          title: 'My Cases',
          icon: Icons.folder_copy_outlined,
          screen: const LawyerCasesScreen(),
        ),
        NavItem(
          title: 'My Bookings',
          icon: Icons.event_available_outlined,
          screen: const LawyerBookingsScreen(),
        ),
        NavItem(
          title: 'My Availability',
          icon: Icons.schedule_outlined,
          screen: const LawyerAvailabilityScreen(),
        ),
      ];
    } else {
      _workspaceSubtitle = role == 'owner' ? 'Owner Panel' : 'Admin Panel';
      _items = [
        NavItem(
          title: 'Dashboard',
          icon: Icons.dashboard,
          screen: DashboardScreen(onNavigate: _selectByTitle),
        ),
        NavItem(title: 'Lawyers', icon: Icons.gavel, screen: const LawyersScreen()),
        NavItem(title: 'Categories', icon: Icons.category, screen: const CategoriesScreen()),
        NavItem(title: 'Users', icon: Icons.people, screen: const UsersScreen()),
        NavItem(title: 'Cases', icon: Icons.folder_copy, screen: const CasesScreen()),
        NavItem(
          title: 'Bookings',
          icon: Icons.event_available,
          screen: const BookingsScreen(),
        ),
        NavItem(title: 'Reviews', icon: Icons.star, screen: const ReviewsScreen()),
        NavItem(
          title: 'Plans',
          icon: Icons.subscriptions,
          screen: const PlansScreen(),
        ),
        NavItem(
          title: 'Subscriptions',
          icon: Icons.card_membership,
          screen: const SubscriptionsScreen(),
        ),
        NavItem(
          title: 'Notifications',
          icon: Icons.notifications,
          screen: const NotificationsScreen(),
        ),
        NavItem(title: 'Chats', icon: Icons.message, screen: const ChatsScreen()),
      ];
    }
    _current = _items.first;
  }

  void _select(NavItem item) => setState(() => _current = item);

  void _selectByTitle(String title) {
    final item = _items.firstWhere(
      (e) => e.title == title,
      orElse: () => _items.first,
    );
    _select(item);
  }

  void _logout() => AuthProvider.of(context).signOut();

  @override
  Widget build(BuildContext context) {
    return AdminNav(
      items: _items,
      current: _current!,
      subtitle: _workspaceSubtitle,
      select: _select,
      logout: _logout,
      child: AppScaffold(
        title: _current!.title,
        body: KeyedSubtree(
          key: ValueKey(_current!.title),
          child: _current!.screen,
        ),
      ),
    );
  }
}
