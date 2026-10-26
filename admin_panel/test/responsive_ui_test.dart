// Responsive navigation and shared-component tests (UI redesign).
//
// These are code-level checks run with flutter_test at fixed logical
// viewport sizes. Any RenderFlex overflow raised during a test fails it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_admin/main.dart';
import 'package:legal_admin/providers/auth_provider.dart';
import 'package:legal_admin/widgets/common.dart';

import 'fakes.dart';

Map<String, dynamic> _emptyPage() => <String, dynamic>{
  'success': true,
  'data': <String, dynamic>{
    'items': <Map<String, dynamic>>[],
    'total': 0,
    'page': 1,
    'limit': 100,
    'totalPages': 0,
  },
};

Map<String, dynamic> _stats() => <String, dynamic>{
  'success': true,
  'data': <String, dynamic>{
    'users': 1284,
    'lawyers': 46,
    'cases': 312,
    'bookings': 905,
    'reviews': 418,
    'plans': 3,
    'subscriptions': 227,
    'bookingsByStatus': <String, dynamic>{
      'active': 74,
      'completed': 761,
      'cancelled': 70,
    },
    'totalWalletBalance': 18450.5,
  },
};

const _adminDestinations = <String>[
  'Dashboard',
  'Lawyers',
  'Categories',
  'Cases',
  'Users',
  'Bookings',
  'Reviews',
  'Plans',
  'Subscriptions',
  'Notifications',
  'Chats',
];

/// Required QA widths with a representative height for each.
const _viewports = <Size>[
  Size(320, 640),
  Size(375, 812),
  Size(430, 932),
  Size(768, 1024),
  Size(1024, 768),
  Size(1366, 768),
  Size(1440, 900),
];

Future<AuthProvider> _pumpAdmin(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final provider = AuthProvider(
    FakeAuthService(
      api: FakeApiService(
        result: _emptyPage(),
        resultsByPath: <String, Object?>{'dashboard/stats': _stats()},
      ),
      restoredSession: adminSession(),
    ),
  );
  await provider.restore();
  await tester.pumpWidget(AdminApp(authProvider: provider));
  await tester.pumpAndSettle();
  return provider;
}

Finder get _persistentNav => find
    .byWidgetPredicate((w) => w.key == const Key('app-navigation'))
    .hitTestable();

/// Opens the drawer (compact/medium) or uses the sidebar (expanded) and taps
/// [title]; afterwards the drawer must be closed.
Future<void> _navigate(
  WidgetTester tester,
  String title, {
  required bool viaDrawer,
}) async {
  final Finder scope;
  if (viaDrawer) {
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    scope = find.byType(Drawer);
  } else {
    scope = find.byKey(const Key('app-navigation'));
  }
  final target = find.descendant(of: scope, matching: find.text(title));
  await tester.scrollUntilVisible(
    target,
    80,
    scrollable: find
        .descendant(of: scope, matching: find.byType(Scrollable))
        .first,
  );
  // Bring the entry fully into the list viewport (not under the footer).
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target.hitTestable());
  await tester.pumpAndSettle();
  expect(
    find.byType(Drawer),
    findsNothing,
    reason: 'the drawer must close after choosing "$title"',
  );
}

void main() {
  group('responsive shell', () {
    for (final size in _viewports) {
      final w = size.width.toInt();
      testWidgets(
        '${w}px: every destination is reachable and the drawer closes',
        (tester) async {
          await _pumpAdmin(tester, size);
          final drawerMode = size.width < 1024;

          // Menu button only below the desktop breakpoint; a persistent
          // sidebar/rail from 600 px up.
          expect(
            find.byTooltip('Open navigation menu'),
            drawerMode ? findsOneWidget : findsNothing,
          );
          expect(
            _persistentNav,
            size.width >= 600 ? findsOneWidget : findsNothing,
          );

          for (final title in _adminDestinations.skip(1).followedBy([
            'Dashboard',
          ])) {
            await _navigate(tester, title, viaDrawer: drawerMode);
            // The page title in the header reflects the destination.
            expect(
              tester.widget<Text>(find.byKey(const Key('page-title'))).data,
              title,
            );
          }
        },
      );
    }

    testWidgets(
      'desktop sidebar collapses to a rail with tooltips and expands again',
      (tester) async {
        await _pumpAdmin(tester, const Size(1366, 768));
        final nav = find.byKey(const Key('app-navigation'));
        expect(
          find.descendant(of: nav, matching: find.text('Lawyers')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: nav, matching: find.text('Sign out')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('sidebar-collapse-toggle')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: nav, matching: find.text('Lawyers')),
          findsNothing,
        );
        expect(
          find.descendant(of: nav, matching: find.byTooltip('Lawyers')),
          findsOneWidget,
        );

        // Rail destinations still navigate.
        await tester.tap(
          find.descendant(of: nav, matching: find.byTooltip('Bookings')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Bookings'), findsWidgets);

        await tester.tap(find.byKey(const Key('sidebar-collapse-toggle')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: nav, matching: find.text('Lawyers')),
          findsOneWidget,
        );
      },
    );

    testWidgets('mobile drawer offers a visible sign out', (tester) async {
      final provider = await _pumpAdmin(tester, const Size(375, 812));
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      final signOut = find.descendant(
        of: find.byType(Drawer),
        matching: find.text('Sign out'),
      );
      expect(signOut, findsOneWidget);
      await tester.tap(signOut);
      await tester.pumpAndSettle();
      expect(provider.isAuthenticated, isFalse);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('Escape dismisses the mobile drawer', (tester) async {
      await _pumpAdmin(tester, const Size(375, 812));
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
    });

    testWidgets('dashboard KPIs use real stats and adapt at 320px', (
      tester,
    ) async {
      await _pumpAdmin(tester, const Size(320, 640));
      expect(find.text('1,284'), findsOneWidget);
      expect(find.text('Wallet balance'), findsOneWidget);
      expect(find.text('\$18,450.50'), findsOneWidget);
      // Two KPI cards per row on a 320 px phone.
      final users = tester.getTopLeft(find.text('Users').first);
      final lawyers = tester.getTopLeft(find.text('Lawyers').first);
      expect(users.dy, lawyers.dy);
      expect(lawyers.dx, greaterThan(users.dx));
    });
  });

  group('shared components', () {
    Future<void> pumpAt(WidgetTester tester, double width, Widget child) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
      await tester.pumpAndSettle();
    }

    testWidgets('status and priority badges carry text, not only color', (
      tester,
    ) async {
      await pumpAt(
        tester,
        400,
        const Column(
          children: [
            StatusChip(status: 'Cancelled'),
            PriorityChip(priority: 'High'),
          ],
        ),
      );
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_double_arrow_up), findsOneWidget);
    });

    testWidgets('SearchField clear button resets the query', (tester) async {
      final values = <String>[];
      await pumpAt(tester, 400, SearchField(onChanged: values.add));
      expect(find.byTooltip('Clear search'), findsNothing);
      await tester.enterText(find.byType(TextField), 'lease');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(values, ['lease', '']);
      expect(find.text('lease'), findsNothing);
    });

    testWidgets(
      'ListToolbar wraps filters on a 320px screen without overflow',
      (tester) async {
        await pumpAt(
          tester,
          320,
          ListToolbar(
            search: SearchField(onChanged: (_) {}),
            filters: [
              for (final label in ['Status', 'Priority', 'Category', 'Lawyer'])
                FilterDropdown<String>(
                  label: label,
                  value: '',
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All')),
                  ],
                  onChanged: (_) {},
                ),
            ],
            actions: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
            ],
            primary: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('Add Case'),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        // Two filters per row.
        expect(
          tester.getTopLeft(find.text('Status')).dy,
          tester.getTopLeft(find.text('Priority')).dy,
        );
        expect(
          tester.getTopLeft(find.text('Category')).dy,
          greaterThan(tester.getTopLeft(find.text('Status')).dy),
        );
        expect(find.text('Add Case'), findsOneWidget);
      },
    );

    testWidgets('RecordTile moves badges under the text on narrow rows', (
      tester,
    ) async {
      Widget tile() => ListView(
        children: [
          RecordTile(
            title: 'Custody hearing preparation for a long case title',
            details: const [
              'Omar Hassan',
              'Commercial Law',
              'Lawyer: Counsel Omar Hassan',
              'Due 2026-11-11',
            ],
            badges: const [
              PriorityChip(priority: 'Medium'),
              StatusChip(status: 'In Progress'),
            ],
            actions: [
              RowAction(
                icon: Icons.edit,
                tooltip: 'Edit case',
                onPressed: () {},
              ),
              RowAction(
                icon: Icons.delete,
                tooltip: 'Delete case',
                destructive: true,
                onPressed: () {},
              ),
            ],
          ),
        ],
      );
      await pumpAt(tester, 320, tile());
      expect(tester.takeException(), isNull);
      final title = tester.getRect(find.textContaining('Custody hearing'));
      final badge = tester.getRect(find.text('Medium'));
      expect(
        badge.top,
        greaterThan(title.bottom),
        reason: 'badges sit below the title on narrow rows',
      );
      expect(find.byTooltip('Edit case'), findsOneWidget);

      await pumpAt(tester, 1200, tile());
      final wideTitle = tester.getRect(find.textContaining('Custody hearing'));
      final wideBadge = tester.getRect(find.text('Medium'));
      expect(
        wideBadge.left,
        greaterThan(wideTitle.right),
        reason: 'badges sit beside the text on wide rows',
      );
    });

    testWidgets('ResponsiveGrid derives the column count from the width', (
      tester,
    ) async {
      Widget grid() => ResponsiveGrid(
        children: [
          for (var i = 0; i < 4; i++)
            SizedBox(height: 40, child: Text('cell $i')),
        ],
      );
      await pumpAt(tester, 300, grid());
      expect(
        tester.getTopLeft(find.text('cell 0')).dy,
        tester.getTopLeft(find.text('cell 1')).dy,
      );
      expect(
        tester.getTopLeft(find.text('cell 2')).dy,
        greaterThan(tester.getTopLeft(find.text('cell 0')).dy),
      );

      await pumpAt(tester, 1000, grid());
      expect(
        tester.getTopLeft(find.text('cell 3')).dy,
        tester.getTopLeft(find.text('cell 0')).dy,
      );
    });
  });
}
