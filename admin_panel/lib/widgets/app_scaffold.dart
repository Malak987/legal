import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';
import '../providers/auth_provider.dart';

/// Navigation item shown in the sidebar, rail and drawer.
class NavItem {
  final String title;
  final IconData icon;
  final Widget screen;

  /// Optional section label; consecutive items with the same group are
  /// listed under one heading.
  final String? group;

  const NavItem({
    required this.title,
    required this.icon,
    required this.screen,
    this.group,
  });
}

/// Responsive app shell.
///
/// * compact  (< 600 px): header with a menu button that opens a navigation
///   [Drawer]; the drawer closes after a destination is chosen.
/// * medium   (600–1023 px): a collapsed icon rail with tooltips, plus the
///   same menu button for the labelled drawer.
/// * expanded (≥ 1024 px): a persistent sidebar that can be collapsed to the
///   rail and expanded again.
///
/// Everything lives in one [Scaffold], so SnackBars, dialogs and the drawer
/// share the same overlay and nothing is hidden behind a nested scaffold.
class AppScaffold extends StatefulWidget {
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
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  /// User choice on desktop; null follows the default (expanded).
  bool? _desktopCollapsed;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = AppBreakpoints.isCompact(width);
    final expanded = AppBreakpoints.isExpanded(width);
    final collapsed = expanded ? (_desktopCollapsed ?? false) : true;
    final showMenu = !expanded;

    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(
          title: widget.title,
          actions: widget.actions,
          showMenu: showMenu,
          showBack: widget.showBack,
          compact: compact,
        ),
        Expanded(child: widget.body),
      ],
    );

    return Scaffold(
      drawer: showMenu
          ? Drawer(
              width: math.min(304, width - 56),
              child: const _NavPanel(mode: _NavMode.drawer),
            )
          : null,
      floatingActionButton: widget.floatingActionButton,
      body: SafeArea(
        child: compact
            ? page
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.centerLeft,
                    child: _NavPanel(
                      mode: collapsed ? _NavMode.rail : _NavMode.sidebar,
                      onToggleCollapsed: expanded
                          ? () => setState(() => _desktopCollapsed = !collapsed)
                          : null,
                    ),
                  ),
                  Expanded(child: page),
                ],
              ),
      ),
    );
  }
}

enum _NavMode { sidebar, rail, drawer }

enum _AccountAction { signOut }

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

String _roleLabel(String role) => switch (role) {
      'owner' => 'Owner',
      'admin' => 'Administrator',
      'lawyer' => 'Lawyer',
      _ => role,
    };

/// Page header: menu button (compact/medium), title, page actions and the
/// signed-in account menu.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.showMenu,
    required this.showBack,
    required this.compact,
    this.actions,
  });

  final String title;
  final bool showMenu;
  final bool showBack;
  final bool compact;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppTheme.surface,
      child: Container(
        height: 60,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        padding: EdgeInsets.symmetric(horizontal: compact ? AppSpacing.xs : AppSpacing.xl),
        child: Row(
          children: [
            if (showMenu)
              Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            if (showBack) const BackButton(),
            if (showMenu || showBack) const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  key: const Key('page-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: compact ? theme.textTheme.titleMedium!.copyWith(fontSize: 17) : theme.textTheme.titleLarge,
                ),
              ),
            ),
            ...?actions,
            const SizedBox(width: AppSpacing.xs),
            _AccountMenu(compact: compact),
          ],
        ),
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final nav = AdminNav.of(context);
    final session = AuthProvider.watchOf(context).session;
    final name = session?.name ?? 'Signed in';
    final email = session?.email ?? '';
    final role = _roleLabel(session?.role ?? '');
    final theme = Theme.of(context);

    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: const Color(0xFFE6ECF7),
      child: Text(
        _initials(name),
        style: theme.textTheme.labelMedium!.copyWith(color: AppTheme.primary),
      ),
    );

    return PopupMenuButton<_AccountAction>(
      tooltip: 'Account',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      onSelected: (action) {
        if (action == _AccountAction.signOut) nav.logout();
      },
      itemBuilder: (context) => [
        PopupMenuItem<_AccountAction>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleSmall),
              if (email.isNotEmpty) Text(email, style: theme.textTheme.bodySmall),
              if (role.isNotEmpty) Text(role, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<_AccountAction>(
          value: _AccountAction.signOut,
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: AppTheme.danger),
              SizedBox(width: AppSpacing.md),
              Text('Sign out'),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            avatar,
            if (!compact) ...[
              const SizedBox(width: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                    Text(role, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.expand_more, size: 18, color: AppTheme.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

/// The navigation surface used as sidebar, rail and drawer content.
class _NavPanel extends StatelessWidget {
  const _NavPanel({required this.mode, this.onToggleCollapsed});

  final _NavMode mode;
  final VoidCallback? onToggleCollapsed;

  bool get _rail => mode == _NavMode.rail;

  void _choose(BuildContext context, NavItem item) {
    final nav = AdminNav.of(context);
    if (mode == _NavMode.drawer) Scaffold.of(context).closeDrawer();
    nav.select(item);
  }

  void _logout(BuildContext context) {
    final nav = AdminNav.of(context);
    if (mode == _NavMode.drawer) Scaffold.of(context).closeDrawer();
    nav.logout();
  }

  @override
  Widget build(BuildContext context) {
    final nav = AdminNav.of(context);
    final width = switch (mode) {
      _NavMode.sidebar => 264.0,
      _NavMode.rail => 76.0,
      _NavMode.drawer => double.infinity,
    };

    final children = <Widget>[];
    String? lastGroup;
    for (final item in nav.items) {
      if (item.group != null && item.group != lastGroup) {
        children.add(_rail
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 22, vertical: AppSpacing.sm),
                child: Divider(color: Color(0x1FFFFFFF)),
              )
            : _GroupLabel(item.group!));
      }
      lastGroup = item.group;
      children.add(_NavTile(
        icon: item.icon,
        label: item.title,
        selected: item.title == nav.current.title,
        rail: _rail,
        onTap: () => _choose(context, item),
      ));
    }

    final panel = Material(
      key: const Key('app-navigation'),
      color: AppTheme.sidebar,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Brand(
              subtitle: nav.subtitle,
              rail: _rail,
              onCollapse: _rail ? null : onToggleCollapsed,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                children: children,
              ),
            ),
            const Divider(color: Color(0x1FFFFFFF)),
            const SizedBox(height: AppSpacing.sm),
            _NavTile(
              icon: Icons.logout,
              label: 'Sign out',
              selected: false,
              rail: _rail,
              onTap: () => _logout(context),
            ),
            if (onToggleCollapsed != null && _rail)
              _NavTile(
                key: const Key('sidebar-collapse-toggle'),
                icon: Icons.keyboard_double_arrow_right,
                label: 'Expand sidebar',
                selected: false,
                rail: _rail,
                onTap: onToggleCollapsed!,
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );

    if (mode != _NavMode.drawer) return panel;
    // Escape closes the drawer, like tapping the scrim or pressing Back.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Scaffold.of(context).closeDrawer(),
      },
      child: FocusScope(autofocus: true, child: panel),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.subtitle, required this.rail, this.onCollapse});

  final String subtitle;
  final bool rail;

  /// Desktop sidebar only: collapses it to the icon rail.
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final logo = Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: AppTheme.gold,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: const Icon(Icons.gavel_rounded, color: AppTheme.sidebar, size: 20),
    );
    return Container(
      height: 64,
      padding: EdgeInsets.only(left: rail ? 0 : 20, right: rail ? 0 : (onCollapse == null ? 20 : 8)),
      alignment: rail ? Alignment.center : Alignment.centerLeft,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      child: rail
          ? Tooltip(message: 'Legal Services · $subtitle', child: logo)
          : Row(
              children: [
                logo,
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Legal Services',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.sidebarText, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (onCollapse != null)
                  IconButton(
                    key: const Key('sidebar-collapse-toggle'),
                    tooltip: 'Collapse sidebar',
                    onPressed: onCollapse,
                    color: AppTheme.sidebarText,
                    hoverColor: AppTheme.sidebarHover,
                    icon: const Icon(Icons.keyboard_double_arrow_left, size: 20),
                  ),
              ],
            ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, AppSpacing.md, 16, AppSpacing.xs + 2),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0x99C9D2E3),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.rail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool rail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppTheme.sidebarText;
    final tile = Material(
      color: selected ? AppTheme.sidebarActive : Colors.transparent,
      borderRadius: AppRadius.mdAll,
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        hoverColor: AppTheme.sidebarHover,
        focusColor: const Color(0x33FFFFFF),
        splashColor: const Color(0x1FFFFFFF),
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (selected)
                const Positioned(
                  left: 0,
                  top: 9,
                  bottom: 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppTheme.gold,
                      borderRadius: BorderRadius.horizontal(right: Radius.circular(3)),
                    ),
                    child: SizedBox(width: 3),
                  ),
                ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: rail ? 0 : 14),
                child: Row(
                  mainAxisAlignment: rail ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: [
                    Icon(icon, color: fg, size: 20),
                    if (!rail) ...[
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fg,
                            fontSize: 14,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Semantics(
        button: true,
        selected: selected,
        label: rail ? label : null,
        child: rail ? Tooltip(message: label, preferBelow: false, child: tile) : tile,
      ),
    );
  }
}

/// InheritedWidget that holds the navigation state and screens.
class AdminNav extends InheritedWidget {
  const AdminNav({
    super.key,
    required this.items,
    required this.current,
    this.subtitle = 'Admin Panel',
    required this.select,
    required this.logout,
    required super.child,
  });

  final List<NavItem> items;
  final NavItem current;
  final String subtitle;
  final ValueChanged<NavItem> select;
  final VoidCallback logout;

  static AdminNav of(BuildContext context) {
    final nav = context.dependOnInheritedWidgetOfExactType<AdminNav>();
    assert(nav != null, 'AdminNav not found in widget tree');
    return nav!;
  }

  @override
  bool updateShouldNotify(AdminNav oldWidget) =>
      oldWidget.current != current ||
      oldWidget.items != items ||
      oldWidget.subtitle != subtitle;
}
