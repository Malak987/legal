// Widget tests for the admin case dialog's client picker (Phase 2A).
//
// The dialog is exercised against [FakeApiService] only: `GET users` stands in
// for the real admin-only users endpoint, and `POST/PUT cases` assert on the
// exact payload the panel would send. No Firebase project, no network.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_admin/models/models.dart';
import 'package:legal_admin/providers/auth_provider.dart';
import 'package:legal_admin/screens/cases_screen.dart';
import 'package:legal_admin/services/api_service.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

/// The backend envelope: `{ success, message, data }` (see `ok()` in
/// `backend/src/utils/response.js`), with the list shape produced by
/// `listDocs()`.
Map<String, dynamic> listPayload(List<Map<String, dynamic>> items) => {
      'success': true,
      'message': 'OK',
      'data': {
        'items': items,
        'total': items.length,
        'page': 1,
        'limit': 100,
        'totalPages': 1,
      },
    };

/// The single-object envelope returned by `GET /api/users/:id`.
Map<String, dynamic> objectPayload(Map<String, dynamic> data) => {
      'success': true,
      'message': 'OK',
      'data': data,
    };

/// A user document exactly as the backend returns it.
Map<String, dynamic> userJson(
  String id,
  String name, {
  String role = 'client',
  String email = '',
  String phone = '',
}) =>
    {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
    };

/// Hosts the dialog on a pushed route, so `Navigator.pop` after a successful
/// save behaves as it does in the app.
class _Launcher extends StatelessWidget {
  const _Launcher({this.item});

  final CaseItem? item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => CaseDialog(item: item)),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

/// Opens the dialog and lets the initial `GET users` settle.
Future<void> openDialog(
  WidgetTester tester,
  FakeApiService api, {
  CaseItem? item,
}) async {
  api.setDefaultResult(
    'categories',
    listPayload([
      {'id': 'family-category', 'name': 'Family Law', 'slug': 'family-law'},
    ]),
  );
  api.setDefaultResult(
    'lawyers',
    listPayload([
      {
        'id': 'family-lawyer',
        'name': 'Family Counsel',
        'categoryId': 'family-category',
        'specialty': 'Family Law',
      },
    ]),
  );
  final provider = AuthProvider(FakeAuthService(api: api));
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: provider,
      child: MaterialApp(home: _Launcher(item: item)),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump(); // route push
  await tester.pump(const Duration(milliseconds: 400)); // transition
  await tester.pump(); // initial users request
  await tester.pump(); // rebuild with results
  await tester.pumpAndSettle(); // categories and lawyer lookup responses
}

/// Types into a labelled text field.
Future<void> typeInto(WidgetTester tester, String label, String value) async {
  await tester.enterText(find.widgetWithText(TextField, label), value);
  await tester.pump();
}

/// Taps Save and lets the request settle.
Future<void> tapSave(WidgetTester tester) async {
  await tester.tap(find.text('Save'));
  await tester.pump();
  await tester.pump();
}

Future<void> chooseFamilyAssignment(WidgetTester tester) async {
  final categoryField = find.text('Select a legal category');
  await tester.ensureVisible(categoryField);
  await tester.pumpAndSettle();
  await tester.tap(categoryField);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Family Law'));
  await tester.pumpAndSettle();

  final lawyerField = find.text('Select a lawyer');
  await tester.ensureVisible(lawyerField);
  await tester.tap(lawyerField);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Family Counsel'));
  await tester.pumpAndSettle();
}

void main() {
  group('case list relations', () {
    testWidgets('renders API-provided category and assigned lawyer names',
        (tester) async {
      final api = FakeApiService(resultsByPath: {
        'cases': listPayload([
          {
            'id': 'case-1',
            'title': 'Contract dispute',
            'clientName': 'Nour Hassan',
            'caseType': 'Commercial Law',
            'categoryId': 'category-1',
            'categoryName': 'Commercial Law',
            'lawyerId': 'lawyer-1',
            'lawyerName': 'Mona Fahmy',
            'dueDate': '2026-12-02',
            'priority': 'High',
            'status': 'In Progress',
          },
        ]),
      });
      final provider = AuthProvider(FakeAuthService(api: api));

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(body: CasesScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Contract dispute'), findsOneWidget);
      expect(find.textContaining('Commercial Law'), findsOneWidget);
      expect(find.textContaining('Lawyer: Mona Fahmy'), findsOneWidget);
    });
  });

  group('client picker: loading and results', () {
    testWidgets('shows a spinner, then the client list', (tester) async {
      // Held open so the loading state is observable regardless of how many
      // microtasks a pump happens to flush.
      final gate = Completer<void>();
      final api = FakeApiService(resultsByPath: {
        'users': listPayload([
          userJson('client-1', 'Sara Ali', email: 'sara@example.com'),
        ]),
      })..gate = gate;

      final provider = AuthProvider(FakeAuthService(api: api));
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: provider,
          child: const MaterialApp(home: _Launcher()),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The dialog is up and the users request has not answered yet.
      expect(find.text('Search clients'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Sara Ali'), findsOneWidget);
      // Enough identity to tell two same-named clients apart.
      expect(find.textContaining('sara@example.com'), findsOneWidget);
    });

    testWidgets('asks for role=client with the endpoint maximum page size',
        (tester) async {
      final api = FakeApiService(resultsByPath: {
        'users': listPayload([userJson('client-1', 'Sara Ali')]),
      });

      await openDialog(tester, api);

      final request = api.requestsFor('GET', 'users').single;
      expect(request.query['role'], 'client');
      expect(request.query['page'], '1');
      expect(request.query['limit'], '100');
      expect(request.query.containsKey('search'), isFalse);
    });

    testWidgets('never lists an account whose raw role is not client',
        (tester) async {
      final api = FakeApiService(resultsByPath: {
        'users': listPayload([
          userJson('client-1', 'Real Client'),
          userJson('admin-1', 'Admin Person', role: 'admin'),
          // No `role` key at all: AppUser.fromJson would default it to
          // 'client', which must not make this account selectable.
          {'id': 'ghost-1', 'name': 'Roleless Person', 'email': 'g@example.com'},
        ]),
      });

      await openDialog(tester, api);

      expect(find.text('Real Client'), findsOneWidget);
      expect(find.text('Admin Person'), findsNothing);
      expect(find.text('Roleless Person'), findsNothing);
    });
  });

  group('client picker: search, empty and error states', () {
    testWidgets('debounces the search and sends it as `search`',
        (tester) async {
      final api = FakeApiService(resultsByPath: {
        'users': listPayload([userJson('client-1', 'Sara Ali')]),
      });
      await openDialog(tester, api);

      await typeInto(tester, 'Search clients', 'sara');
      // Inside the debounce window: no extra request yet.
      expect(api.requestsFor('GET', 'users'), hasLength(1));

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final requests = api.requestsFor('GET', 'users');
      expect(requests, hasLength(2));
      expect(requests.last.query['search'], 'sara');
      expect(requests.last.query['role'], 'client');
    });

    testWidgets('shows an empty state when no client matches', (tester) async {
      final api = FakeApiService(resultsByPath: {'users': listPayload([])});

      await openDialog(tester, api);

      expect(find.text('No clients found.'), findsOneWidget);
    });

    testWidgets('shows an error with a working retry', (tester) async {
      final results = <String, Object?>{
        'users': ApiException('server exploded', 500),
      };
      final api = FakeApiService(resultsByPath: results);

      await openDialog(tester, api);

      expect(find.textContaining('Could not load clients.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Recover: the same map instance backs the fake.
      results['users'] = listPayload([userJson('client-1', 'Sara Ali')]);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Could not load clients.'), findsNothing);
      expect(find.text('Sara Ali'), findsOneWidget);
    });
  });

  group('client selection and create', () {
    testWidgets('selecting a result marks it as the owner', (tester) async {
      final api = FakeApiService(resultsByPath: {
        'users': listPayload([
          userJson('client-1', 'Sara Ali', email: 'sara@example.com'),
        ]),
      });
      await openDialog(tester, api);

      await tester.tap(find.text('Sara Ali'));
      await tester.pump();

      expect(find.textContaining('Owner: Sara Ali (client-1)'), findsOneWidget);
      // The display/legacy field follows an explicit pick.
      expect(find.widgetWithText(TextField, 'Sara Ali'), findsOneWidget);
    });

    testWidgets('creating sends the selected real userId', (tester) async {
      final api = FakeApiService(resultsByPath: {
        'users': listPayload([
          userJson('client-1', 'Sara Ali', email: 'sara@example.com'),
        ]),
      });
      await openDialog(tester, api);

      await typeInto(tester, 'Title', 'Contract review');
      await tester.tap(find.text('Sara Ali'));
      await tester.pump();
      await chooseFamilyAssignment(tester);
      await tapSave(tester);

      final body = api.lastBodyFor('POST', 'cases') as Map<String, dynamic>;
      expect(body['userId'], 'client-1');
      expect(body['clientName'], 'Sara Ali');
      expect(body['categoryId'], 'family-category');
      expect(body['lawyerId'], 'family-lawyer');
      expect(body['title'], 'Contract review');
      // Unrelated fields keep their defaults.
      expect(body['status'], 'Open');
      expect(body['priority'], 'Medium');
      expect(body.containsKey('warnings'), isFalse);
    });

    testWidgets('does not submit an admin-owned case without a client',
        (tester) async {
      final api = FakeApiService(resultsByPath: {
        'users': listPayload([userJson('client-1', 'Sara Ali')]),
      });
      await openDialog(tester, api);

      await typeInto(tester, 'Title', 'No client picked');
      // A typed name is not an owner.
      await typeInto(tester, 'Client name', 'Typed Only');
      await tapSave(tester);

      expect(api.requestsFor('POST', 'cases'), isEmpty);
      expect(find.text('Select a client for this case.'), findsOneWidget);
    });
  });

  group('editing an existing case', () {
    testWidgets('preselects an owner that really is a client',
        (tester) async {
      final api = FakeApiService(resultsByPath: {
        'users': listPayload([
          userJson('client-1', 'Sara Ali', email: 'sara@example.com'),
        ]),
        'users/client-1': objectPayload(
          userJson('client-1', 'Sara Ali', email: 'sara@example.com'),
        ),
      });

      await openDialog(
        tester,
        api,
        item: CaseItem(
          id: 'case-1',
          title: 'Existing case',
          clientName: 'Legacy Display Name',
          userId: 'client-1',
        ),
      );

      expect(find.textContaining('Owner: Sara Ali (client-1)'), findsOneWidget);
      // The stored display name is not overwritten by the lookup.
      expect(find.widgetWithText(TextField, 'Legacy Display Name'),
          findsOneWidget);
      expect(find.textContaining('not a client account'), findsNothing);

      await tapSave(tester);

      final body = api.lastBodyFor('PUT', 'cases/case-1') as Map<String, dynamic>;
      expect(body['userId'], 'client-1');
      expect(body['clientName'], 'Legacy Display Name');
    });

    testWidgets('warns and preserves the owner when it no longer exists',
        (tester) async {
      final api = FakeApiService(resultsByPath: {
        'users': listPayload([userJson('client-1', 'Sara Ali')]),
        'users/client-9': ApiException('User not found', 404),
      });

      await openDialog(
        tester,
        api,
        item: CaseItem(id: 'case-1', title: 'Ghost owner', userId: 'client-9'),
      );

      expect(find.textContaining('stored owner no longer exists'),
          findsOneWidget);

      await tapSave(tester);

      final body = api.lastBodyFor('PUT', 'cases/case-1') as Map<String, dynamic>;
      // Omitted `userId` is what leaves the stored owner untouched.
      expect(body.containsKey('userId'), isFalse);
    });

    testWidgets('warns and preserves the owner when it is not a client',
        (tester) async {
      final api = FakeApiService(resultsByPath: {
        'users': listPayload([userJson('client-1', 'Sara Ali')]),
        // The Phase 1 defect: an admin-created case owned by the admin.
        'users/admin-1': objectPayload(
          userJson('admin-1', 'Admin Person', role: 'admin', email: 'a@example.com'),
        ),
      });

      await openDialog(
        tester,
        api,
        item: CaseItem(
          id: 'case-1',
          title: 'Admin owned',
          clientName: 'Admin Person',
          userId: 'admin-1',
        ),
      );

      expect(find.textContaining('is not a client account'), findsOneWidget);
      expect(find.textContaining('Owner:'), findsNothing);

      await tapSave(tester);

      final body = api.lastBodyFor('PUT', 'cases/case-1') as Map<String, dynamic>;
      expect(body.containsKey('userId'), isFalse);
    });

    testWidgets('an explicit replacement is sent and applied', (tester) async {
      final api = FakeApiService(resultsByPath: {
        'users': listPayload([
          userJson('client-2', 'Replacement Client', email: 'r@example.com'),
        ]),
        'users/admin-1': objectPayload(
          userJson('admin-1', 'Admin Person', role: 'admin'),
        ),
      });

      await openDialog(
        tester,
        api,
        item: CaseItem(id: 'case-1', title: 'Admin owned', userId: 'admin-1'),
      );
      expect(find.textContaining('is not a client account'), findsOneWidget);

      await tester.tap(find.text('Replacement Client'));
      await tester.pump();
      await tapSave(tester);

      final body = api.lastBodyFor('PUT', 'cases/case-1') as Map<String, dynamic>;
      expect(body['userId'], 'client-2');
      expect(body['clientName'], 'Replacement Client');
    });
  });
}
