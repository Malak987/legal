// Regression tests for the admin UI completeness fixes (audit 2026-10-26).
//
// Every assertion is on the exact payload sent to [FakeApiService], i.e. the
// fields that reach the Supabase adapter. No network and no Supabase project.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_admin/models/models.dart';
import 'package:legal_admin/providers/auth_provider.dart';
import 'package:legal_admin/screens/bookings_screen.dart';
import 'package:legal_admin/screens/lawyers_screen.dart';
import 'package:legal_admin/screens/notifications_screen.dart';
import 'package:legal_admin/screens/plans_screen.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

Map<String, dynamic> _list(List<Map<String, dynamic>> items) => {
      'success': true,
      'data': {
        'items': items,
        'total': items.length,
        'page': 1,
        'limit': 100,
        'totalPages': 1,
      },
    };

/// Hosts [child] behind an "open" button so `Navigator.pop` behaves as in
/// the app.
Future<void> _open(WidgetTester tester, FakeApiService api, Widget child) async {
  // Tall surface so long dialogs do not need scrolling in the test.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: AuthProvider(FakeAuthService(api: api)),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => child),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('PlanDialog', () {
    testWidgets('keeps a colour outside the palette and saves priceValue',
        (tester) async {
      final api = FakeApiService();
      await _open(
        tester,
        api,
        PlanDialog(
          plan: Plan(
            id: 'plan-1',
            title: 'Gold',
            price: r'$29 / month',
            priceValue: 29,
            color: '#3A86FF', // public.plans default, not in the palette
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Current (#3A86FF)'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Numeric price (e.g. 29)'), '49.5');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final body = api.lastBodyFor('PUT', 'plans/plan-1') as Map<String, dynamic>;
      expect(body['priceValue'], 49.5);
      expect(body['color'], '#3A86FF');
      expect(body['title'], 'Gold');
    });

    testWidgets('rejects a one-character title (plans.title CHECK)', (tester) async {
      final api = FakeApiService();
      await _open(tester, api, const PlanDialog());
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'G');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(api.requestsFor('POST', 'plans'), isEmpty);
      expect(find.text('Title must be at least 2 characters', skipOffstage: false), findsOneWidget);
    });
  });

  group('NotificationDialog', () {
    testWidgets('requires a recipient and omits an empty type', (tester) async {
      final api = FakeApiService(resultsByPath: {
        'users': _list([
          {'id': 'client-1', 'name': 'Sara Ali', 'role': 'client'},
        ]),
      });
      await _open(tester, api, const NotificationDialog());

      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Hearing moved');
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(api.requestsFor('POST', 'notifications'), isEmpty);
      expect(find.text('Select a recipient', skipOffstage: false), findsOneWidget);

      await tester.tap(find.text('Sara Ali'));
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      final body =
          api.lastBodyFor('POST', 'notifications') as Map<String, dynamic>;
      expect(body['userId'], 'client-1');
      expect(body['title'], 'Hearing moved');
      expect(body.containsKey('type'), isFalse);
    });
  });

  group('LawyerDialog', () {
    Future<FakeApiService> openLawyer(WidgetTester tester, Lawyer lawyer) async {
      final api = FakeApiService(resultsByPath: {
        'categories': _list([
          {'id': 'cat-1', 'name': 'Family Law', 'slug': 'family-law'},
        ]),
        'users': _list([
          {'id': 'lawyer-user-1', 'name': 'Omar Lawyer', 'role': 'lawyer'},
        ]),
      });
      await _open(tester, api, LawyerDialog(lawyer: lawyer));
      return api;
    }

    final stored = Lawyer(
      id: 'lawyer-1',
      name: 'Omar Counsel',
      categoryId: 'cat-1',
      priceValue: 150,
      bio: 'Old bio',
    );

    testWidgets('edits the bio and leaves the account link untouched',
        (tester) async {
      final api = await openLawyer(tester, stored);
      expect(find.widgetWithText(TextField, 'Bio'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Bio'), 'Family mediator');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final body =
          api.lastBodyFor('PUT', 'lawyers/lawyer-1') as Map<String, dynamic>;
      expect(body['bio'], 'Family mediator');
      expect(body.containsKey('userId'), isFalse);
    });

    testWidgets('links a lawyer-role account only on an explicit pick',
        (tester) async {
      final api = await openLawyer(tester, stored);

      // The picker is restricted to lawyer-role profiles.
      final usersQuery = api.requestsFor('GET', 'users').last.query;
      expect(usersQuery['role'], 'lawyer');

      await tester.tap(find.text('Omar Lawyer'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final body =
          api.lastBodyFor('PUT', 'lawyers/lawyer-1') as Map<String, dynamic>;
      expect(body['userId'], 'lawyer-user-1');
    });

    testWidgets('requires a positive rate when none is stored', (tester) async {
      final api = await openLawyer(
        tester,
        Lawyer(id: 'lawyer-2', name: 'Legacy', categoryId: 'cat-1', priceValue: 0),
      );
      await tester.enterText(
          find.widgetWithText(TextField, 'Hourly rate (number only, e.g. 150)'), '');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(api.requestsFor('PUT', 'lawyers/lawyer-2'), isEmpty);
    });
  });

  group('BookingsScreen', () {
    testWidgets('offers no status change for a terminal booking', (tester) async {
      final api = FakeApiService(resultsByPath: {
        'bookings': _list([
          {
            'id': 'booking-1',
            'lawyerName': 'Omar Counsel',
            'date': '2026-11-01',
            'time': '10:00',
            'hours': 1,
            'totalPrice': 150,
            'status': 'Completed',
          },
        ]),
      });
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: AuthProvider(FakeAuthService(api: api)),
          child: const MaterialApp(home: Scaffold(body: BookingsScreen())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mark '), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('offers only valid transitions for a pending booking',
        (tester) async {
      final api = FakeApiService(resultsByPath: {
        'bookings': _list([
          {
            'id': 'booking-2',
            'lawyerName': 'Omar',
            'date': '2026-11-02',
            'time': '11:00',
            'hours': 1,
            'totalPrice': 150,
            'status': 'Pending',
          },
        ]),
      });
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: AuthProvider(FakeAuthService(api: api)),
          child: const MaterialApp(home: Scaffold(body: BookingsScreen())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Mark Confirmed'), findsOneWidget);
      expect(find.text('Mark Completed'), findsOneWidget);
      expect(find.text('Mark Cancelled'), findsOneWidget);
    });
  });
}
