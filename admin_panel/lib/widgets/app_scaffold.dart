import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Navigation item shown in the sidebar / drawer.
class NavItem {
  final String title;
  final IconData icon;
  final Widget screen;

  const NavItem({required this.title, required this.icon, required this.screen});
}

/// Reusable app shell: sidebar on wide screens, drawer on narrow screens.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.showBack = false,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    final content = Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: actions,
        automaticallyImplyLeading: showBack,
      ),
      drawer: isWide ? null : const _AdminDrawer(),
      body: body,
      floatingActionButton: floatingActionButton,
    );

    if (!isWide) return content;

    return Scaffold(
      body: Row(
        children: [
          const _Sidebar(),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final nav = AdminNav.of(context);
    final current = nav.current;

    return Material(
      color: AppTheme.primary,
      child: SizedBox(
        width: 250,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.amber,
                      child: Icon(Icons.gavel, color: Colors.white),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Legal Services',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Admin Panel',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final item in nav.items)
                      _SidebarTile(
                        item: item,
                        selected: item.title == current.title,
                        onTap: () {
                          final navState = AdminNav.of(context);
                          navState.select(item);
                        },
                      ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              _SidebarTile(
                item: NavItem(
                  title: 'Logout',
                  icon: Icons.logout,
                  screen: const SizedBox.shrink(),
                ),
                selected: false,
                onTap: () => AdminNav.of(context).logout(),
                color: Colors.redAccent,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tileColor = color ?? (selected ? Colors.white24 : Colors.transparent);
    final fg = color ?? Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: tileColor,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(item.icon, color: fg, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(color: fg, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminDrawer extends StatelessWidget {
  const _AdminDrawer();

  @override
  Widget build(BuildContext context) {
    return const Drawer(child: _Sidebar());
  }
}

/// InheritedWidget that holds the navigation state and screens.
class AdminNav extends InheritedWidget {
  const AdminNav({
    super.key,
    required this.items,
    required this.current,
    required this.select,
    required this.logout,
    required super.child,
  });

  final List<NavItem> items;
  final NavItem current;
  final ValueChanged<NavItem> select;
  final VoidCallback logout;

  static AdminNav of(BuildContext context) {
    final nav = context.dependOnInheritedWidgetOfExactType<AdminNav>();
    assert(nav != null, 'AdminNav not found in widget tree');
    return nav!;
  }

  @override
  bool updateShouldNotify(AdminNav oldWidget) =>
      oldWidget.current != current || oldWidget.items != items;
}
