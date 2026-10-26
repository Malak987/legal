// Phase-2 functional completion: centralized error mapping, shared
// pagination, role change, booking reschedule, review moderation, identity
// enrichment and case filters.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legal_admin/models/models.dart';
import 'package:legal_admin/providers/auth_provider.dart';
import 'package:legal_admin/screens/bookings_screen.dart';
import 'package:legal_admin/screens/cases_screen.dart';
import 'package:legal_admin/screens/categories_screen.dart';
import 'package:legal_admin/screens/reviews_screen.dart';
import 'package:legal_admin/screens/users_screen.dart';
import 'package:legal_admin/services/api_errors.dart';
import 'package:legal_admin/services/api_service.dart';
import 'package:legal_admin/services/auth_service.dart';
import 'package:legal_admin/widgets/pagination.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

Map<String, dynamic> _page(
  List<Map<String, dynamic>> items, {
  int page = 1,
  int? total,
  int limit = 100,
}) {
  final count = total ?? items.length;
  return {
    'success': true,
    'data': {
      'items': items,
      'page': page,
      'limit': limit,
      'total': count,
      'totalPages': count == 0 ? 0 : (count + limit - 1) ~/ limit,
    },
  };
}

/// Answers GET [path] with a page whose `page` echoes the requested page.
class _PagingApi extends FakeApiService {
  _PagingApi(this.pages, {super.resultsByPath});

  final Map<String, Map<String, dynamic> Function(int page)> pages;
  static const int total = 150;

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final builder = pages[path];
    if (builder == null) return super.get(path, query: query);
    await super.get(path, query: query);
    final page = int.tryParse(query?['page'] ?? '1') ?? 1;
    return _page([builder(page)], page: page, total: total);
  }
}

Future<FakeApiService> _pump(
  WidgetTester tester,
  FakeApiService api,
  Widget screen, {
  AdminSession? session,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final provider = AuthProvider(FakeAuthService(api: api, restoredSession: session));
  if (session != null) await provider.restore();
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: provider,
      child: MaterialApp(home: Scaffold(body: screen)),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

ApiService _service(Future<http.Response> Function(http.Request) handler) =>
    ApiService(
      client: MockClient(handler),
      tokenProvider: () async => 'test-user-jwt',
      supabaseUrl: 'https://example.supabase.co',
      supabaseAnonKey: 'test-anon-key',
    );

http.Response _json(Object body, int status, {Map<String, String>? headers}) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json', ...?headers});

void main() {
  group('friendlyError: centralized PostgREST/domain mapping', () {
    test('duplicate category is explained and keeps only the code reference', () {
      final e = ApiException(
        'duplicate key value violates unique constraint "legal_categories_slug_key"',
        409,
        code: '23505',
        details: 'Key (slug)=(family-law) already exists.',
        hint: 'internal hint',
      );
      final text = friendlyError(e);
      expect(text, 'A category with this name already exists. (ref: 23505)');
      expect(text, isNot(contains('family-law')));
      expect(text, isNot(contains('legal_categories_slug_key')));
      // Raw diagnostics stay on the exception and in the debug log text.
      expect(e.message, contains('legal_categories_slug_key'));
      final diagnostics = apiErrorDiagnostics(e);
      expect(diagnostics, contains('code=23505'));
      expect(diagnostics, contains('details=Key (slug)=(family-law) already exists.'));
      expect(diagnostics, contains('hint=internal hint'));
    });

    test('invalid case assignment domain code', () {
      final e = ApiException('INVALID_CASE_ASSIGNMENT', 400, code: 'INVALID_CASE_ASSIGNMENT');
      expect(
        friendlyError(e),
        'The selected lawyer is not assigned to the selected category. '
        '(ref: INVALID_CASE_ASSIGNMENT)',
      );
      // The raw message alone (as RAISE ... MESSAGE delivers it) also maps.
      expect(friendlyError(ApiException('INVALID_CASE_ASSIGNMENT', 400, code: '22023')),
          startsWith('The selected lawyer is not assigned'));
    });

    test('FK restriction names the referencing records, not SQL', () {
      final e = ApiException(
        'update or delete on table "lawyers" violates foreign key constraint '
        '"cases_lawyer_id_fkey" on table "cases"',
        409,
        code: '23503',
        details: 'Key (id)=(lawyer-1) is still referenced from table "cases".',
      );
      final text = friendlyError(e);
      expect(text, startsWith('This record is still used by cases'));
      expect(text, isNot(contains('fkey')));
      expect(text, isNot(contains('lawyer-1')));
    });

    test('missing RPC, view and column point at pending migrations', () {
      expect(friendlyError(ApiException('Could not find the function', 404, code: 'PGRST202')),
          contains('missing server function'));
      expect(friendlyError(ApiException('Could not find the table', 404, code: 'PGRST205')),
          contains('missing table or view'));
      expect(friendlyError(ApiException('column x does not exist', 400, code: '42703')),
          contains('missing a field'));
    });

    test('permission and validation errors', () {
      expect(friendlyError(ApiException('permission denied for table users', 403, code: '42501')),
          'You do not have permission to perform this action. (ref: 42501)');
      expect(friendlyError(ApiException('ADMIN_REQUIRED', 403, code: '42501')),
          'Only administrators can perform this action. (ref: ADMIN_REQUIRED)');
      expect(friendlyError(ApiException('new row violates check constraint "x_title_check"', 400, code: '23514')),
          startsWith('The title must be at least 2 characters.'));
      expect(friendlyError(ApiException('value too long for type character varying(160)', 400, code: '22001')),
          startsWith('One of the values is too long.'));
      expect(friendlyError(ApiException('CANNOT_DEMOTE_LAST_ADMIN', 403, code: '42501')),
          contains('last administrator'));
    });

    test('client-authored messages pass through; unknown codes fall back by status', () {
      expect(friendlyError(ApiException('Select a client for this case.', 400)),
          'Select a client for this case. (ref: HTTP 400)');
      expect(friendlyError(ApiException('some internal failure text', 500, code: 'XX000')),
          'The server could not complete the request. Please try again. (ref: XX000)');
      expect(friendlyError(StateError('boom')), 'Something went wrong. Please try again.');
    });
  });

  group('paginatedOf', () {
    test('treats totalPages 0 as one empty page', () {
      final p = paginatedOf(_page(const []), (j) => j);
      expect(p.total, 0);
      expect(p.totalPages, 1);
      expect(p.hasNext, isFalse);
      expect(p.hasPrevious, isFalse);
    });

    test('computes the visible range and next/previous', () {
      final p = paginatedOf(
        _page([{'id': 'a'}], page: 2, total: 250),
        (j) => j,
      );
      expect(p.firstIndex, 101);
      expect(p.lastIndex, 101);
      expect(p.totalPages, 3);
      expect(p.hasPrevious, isTrue);
      expect(p.hasNext, isTrue);
    });

    test('a full page without an exact total never hides further records', () {
      final items = List.generate(100, (i) => <String, dynamic>{'id': '$i'});
      final p = paginatedOf({'data': {'items': items}}, (j) => j, page: 1, limit: 100);
      expect(p.hasNext, isTrue);
    });

    test('loadPaginated steps back when the requested page became empty', () async {
      final requested = <int>[];
      final p = await loadPaginated<Map<String, dynamic>>(
        page: 3,
        fromJson: (j) => j,
        request: (page) async {
          requested.add(page);
          return page == 3
              ? _page(const [], page: 3, total: 120)
              : _page([{'id': 'x'}], page: page, total: 120);
        },
      );
      expect(requested, [3, 2]);
      expect(p.page, 2);
    });
  });

  group('shared pagination footer', () {
    testWidgets('shows totals and requests the next and previous pages', (tester) async {
      final api = _PagingApi({
        'categories': (page) => {'id': 'cat-$page', 'name': 'Category $page', 'slug': 'c$page'},
      });
      await _pump(tester, api, const CategoriesScreen());

      expect(find.text('Showing 1–1 of 150'), findsOneWidget);
      expect(find.text('Page 1 of 2'), findsOneWidget);
      final previous = tester.widget<IconButton>(find.byKey(const Key('pagination-previous')));
      expect(previous.onPressed, isNull);

      await tester.tap(find.byKey(const Key('pagination-next')));
      await tester.pumpAndSettle();
      expect(api.requestsFor('GET', 'categories').last.query['page'], '2');
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(find.text('Category 2'), findsOneWidget);
      final next = tester.widget<IconButton>(find.byKey(const Key('pagination-next')));
      expect(next.onPressed, isNull);

      await tester.tap(find.byKey(const Key('pagination-previous')));
      await tester.pumpAndSettle();
      expect(api.requestsFor('GET', 'categories').last.query['page'], '1');
    });

    testWidgets('a new search returns to page 1', (tester) async {
      final api = _PagingApi({
        'categories': (page) => {'id': 'cat-$page', 'name': 'Category $page', 'slug': 'c$page'},
      });
      await _pump(tester, api, const CategoriesScreen());
      await tester.tap(find.byKey(const Key('pagination-next')));
      await tester.pumpAndSettle();
      expect(api.requestsFor('GET', 'categories').last.query['page'], '2');

      await tester.enterText(find.byType(TextField).first, 'family');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final last = api.requestsFor('GET', 'categories').last;
      expect(last.query['page'], '1');
      expect(last.query['search'], 'family');
    });

    testWidgets('load failures show the friendly message, not the raw error', (tester) async {
      final api = FakeApiService(resultsByPath: {
        'categories': ApiException(
          'permission denied for table legal_categories',
          403,
          code: '42501',
        ),
      });
      await _pump(tester, api, const CategoriesScreen());
      expect(find.textContaining('You do not have permission'), findsOneWidget);
      expect(find.textContaining('legal_categories'), findsNothing);
    });
  });

  group('case filters', () {
    testWidgets('combine with search and reset pagination', (tester) async {
      final api = _PagingApi(
        {
          'cases': (page) => {
                'id': 'case-$page',
                'title': 'Case $page',
                'status': 'Open',
                'priority': 'High',
              },
        },
        resultsByPath: {
          'categories': _page([{'id': 'cat-1', 'name': 'Family Law', 'slug': 'family'}]),
          'lawyers': _page([{'id': 'law-1', 'name': 'Mona Fahmy'}]),
        },
      );
      await _pump(tester, api, const CasesScreen());

      await tester.tap(find.byKey(const Key('pagination-next')));
      await tester.pumpAndSettle();
      expect(api.requestsFor('GET', 'cases').last.query['page'], '2');

      await tester.tap(find.byKey(const Key('case-filter-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pending').last);
      await tester.pumpAndSettle();
      var last = api.requestsFor('GET', 'cases').last;
      expect(last.query['page'], '1');
      expect(last.query['status'], 'Pending');

      await tester.tap(find.byKey(const Key('case-filter-lawyer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mona Fahmy').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'lease');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      last = api.requestsFor('GET', 'cases').last;
      expect(last.query, containsPair('status', 'Pending'));
      expect(last.query, containsPair('lawyerId', 'law-1'));
      expect(last.query, containsPair('search', 'lease'));
      expect(last.query['page'], '1');

      await tester.tap(find.byKey(const Key('case-filter-clear')));
      await tester.pumpAndSettle();
      last = api.requestsFor('GET', 'cases').last;
      expect(last.query.containsKey('status'), isFalse);
      expect(last.query.containsKey('lawyerId'), isFalse);
      expect(last.query['search'], 'lease');
    });

    testWidgets('lawyer filter is disabled with a reason if its lookup fails', (tester) async {
      final api = FakeApiService(resultsByPath: {
        'cases': _page(const []),
        'categories': _page(const []),
        'lawyers': ApiException('Could not find the function', 404, code: 'PGRST202'),
      });
      await _pump(tester, api, const CasesScreen());
      final dropdown = tester.widget<DropdownButton<String?>>(
        find.byKey(const Key('case-filter-lawyer')),
      );
      expect(dropdown.onChanged, isNull);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: find.byKey(const Key('case-filter-lawyer')), matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, contains('Lawyer filter unavailable'));
      expect(tooltip.message, contains('missing server function'));
    });
  });

  group('role change', () {
    Map<String, dynamic> users() => _page([
          {'id': 'u-1', 'name': 'Sara Ali', 'email': 'sara@example.com', 'role': 'client'},
          {'id': 'owner-9', 'name': 'Root Owner', 'email': 'o@example.com', 'role': 'owner'},
          {'id': 'admin-uid', 'name': 'App Administrator', 'email': 'a@example.com', 'role': 'admin'},
        ]);

    testWidgets('owner rows and the current admin cannot be changed', (tester) async {
      final api = FakeApiService(resultsByPath: {'users': users()});
      await _pump(tester, api, const UsersScreen(), session: adminSession());
      IconButton button(String id) =>
          tester.widget<IconButton>(find.byKey(ValueKey('change-role-$id')));
      expect(button('owner-9').onPressed, isNull);
      expect(button('admin-uid').onPressed, isNull);
      expect(button('u-1').onPressed, isNotNull);
    });

    testWidgets('requires a confirmed change, never offers owner, then re-fetches',
        (tester) async {
      final api = FakeApiService(resultsByPath: {
        'users': users(),
        'users/u-1/role': {
          'success': true,
          'data': {'id': 'u-1', 'name': 'Sara Ali', 'email': 'sara@example.com', 'role': 'lawyer'},
        },
      });
      await _pump(tester, api, const UsersScreen(), session: adminSession());
      final fetchesBefore = api.requestsFor('GET', 'users').length;

      await tester.tap(find.byKey(const ValueKey('change-role-u-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('role-option-owner')), findsNothing);
      for (final role in ['client', 'lawyer', 'admin']) {
        expect(find.byKey(ValueKey('role-option-$role')), findsOneWidget);
      }
      expect(find.textContaining('read-only lawyer workspace'), findsOneWidget);
      // Nothing changed yet: confirmation is disabled.
      final confirm = find.widgetWithText(ElevatedButton, 'Change role');
      expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('role-option-lawyer')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Change to Lawyer'));
      await tester.pumpAndSettle();

      expect(api.lastBodyFor('PUT', 'users/u-1/role'), {'role': 'lawyer'});
      expect(api.requestsFor('GET', 'users').length, fetchesBefore + 1);
      expect(find.text('Sara Ali is now a lawyer', skipOffstage: false), findsOneWidget);
    });

    testWidgets('missing rpc_admin_set_user_role is reported as a deployment dependency',
        (tester) async {
      final api = FakeApiService(resultsByPath: {
        'users': users(),
        'users/u-1/role': ApiException('Could not find the function', 404, code: 'PGRST202'),
      });
      await _pump(tester, api, const UsersScreen(), session: adminSession());
      await tester.tap(find.byKey(const ValueKey('change-role-u-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('role-option-admin')));
      await tester.pumpAndSettle();
      expect(find.textContaining('grants full administrative access'), findsWidgets);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Change to Admin'));
      await tester.pumpAndSettle();
      expect(find.textContaining('20261025142000'), findsOneWidget);
      expect(find.textContaining('No change was made'), findsOneWidget);
      // Only the RPC route was attempted; no other write was issued.
      expect(api.requests.where((r) => r.method != 'GET').map((r) => r.path),
          ['users/u-1/role']);
    });

    test('ApiService refuses to assign owner without any request', () async {
      var requests = 0;
      final api = _service((request) async {
        requests++;
        return _json({}, 200);
      });
      await expectLater(
        api.put('users/u-1/role', body: {'role': 'owner'}),
        throwsA(isA<ApiException>()),
      );
      expect(requests, 0);
    });
  });

  group('booking reschedule', () {
    test('time validation follows the RPC contract', () {
      expect(RescheduleBookingDialog.validateTime('9:30', 2), isNull);
      expect(RescheduleBookingDialog.validateTime('23:00', 1), isNull);
      expect(RescheduleBookingDialog.validateTime('23:30', 1), isNotNull);
      expect(RescheduleBookingDialog.validateTime('24:00', 1), isNotNull);
      expect(RescheduleBookingDialog.validateTime('9:3', 1), isNotNull);
      expect(RescheduleBookingDialog.validateTime('09:60', 1), isNotNull);
      expect(RescheduleBookingDialog.validateTime('9am', 1), isNotNull);
    });

    Map<String, dynamic> booking(String status) => _page([
          {
            'id': 'b-1',
            'lawyerId': 'law-1',
            'lawyerName': 'Mona Fahmy',
            'userId': 'u-1',
            'userName': 'Sara Ali',
            'userEmail': 'sara@example.com',
            'date': '2099-01-15',
            'time': '10:00',
            'hours': 2,
            'totalPrice': 200,
            'status': status,
          },
        ]);

    testWidgets('shows the client and sends date/time/hours with the same lawyer',
        (tester) async {
      final api = FakeApiService(resultsByPath: {
        'bookings': booking('Pending'),
        'bookings/b-1': {'success': true, 'data': {'id': 'b-1'}},
      });
      await _pump(tester, api, const BookingsScreen());
      expect(find.textContaining('Client: Sara Ali (sara@example.com)'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reschedule…'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('reschedule-time')), '25:00');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reschedule'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a 24-hour time such as 09:30'), findsOneWidget);
      expect(api.requestsFor('PUT', 'bookings/b-1'), isEmpty);

      await tester.enterText(find.byKey(const Key('reschedule-time')), '9:30');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reschedule'));
      await tester.pumpAndSettle();
      expect(api.lastBodyFor('PUT', 'bookings/b-1'), {
        'lawyerId': 'law-1',
        'date': '2099-01-15',
        'time': '09:30',
        'hours': 2,
      });
    });

    testWidgets('terminal bookings offer no reschedule', (tester) async {
      final api = FakeApiService(resultsByPath: {'bookings': booking('Completed')});
      await _pump(tester, api, const BookingsScreen());
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Reschedule…'), findsNothing);
    });

    test('a server-side slot conflict maps to a friendly message', () async {
      final api = _service((request) async {
        if (request.url.path.endsWith('/bookings')) {
          return _json([
            {'id': 'b-1', 'lawyer_id': 'law-1', 'date': '2099-01-15', 'time': '10:00', 'hours': 2},
          ], 200);
        }
        return _json({'error': 'SLOT_TAKEN'}, 200);
      });
      try {
        await api.put('bookings/b-1', body: {'date': '2099-01-16', 'time': '09:00', 'hours': 1});
        fail('expected a conflict');
      } on ApiException catch (e) {
        expect(e.code, 'SLOT_TAKEN');
        expect(friendlyError(e), 'That appointment time is no longer available. (ref: SLOT_TAKEN)');
      }
    });
  });

  group('review moderation', () {
    test('the moderation response never carries the reviewer user_id', () async {
      late http.Request rpc;
      final api = _service((request) async {
        rpc = request;
        return _json({
          'id': 'r-1',
          'user_id': 'private-user',
          'user_name': 'Sara',
          'lawyer_id': 'law-1',
          'rating': 4.5,
          'comment': 'ok',
        }, 200);
      });
      final res = await api.put('reviews/r-1', body: {'rating': 4.5});
      expect(rpc.url.path, '/rest/v1/rpc/rpc_admin_review_moderate');
      expect(jsonDecode(rpc.body), {'p_review_id': 'r-1', 'p_rating': 4.5, 'p_comment': null});
      final data = objectDataOf(res);
      expect(data.containsKey('userId'), isFalse);
      expect(data.containsKey('user_id'), isFalse);
      expect(jsonEncode(res), isNot(contains('private-user')));
    });

    testWidgets('lists lawyer names and sends only changed fields', (tester) async {
      final api = FakeApiService(resultsByPath: {
        'reviews': _page([
          {
            'id': 'r-1',
            'userName': 'Sara',
            'lawyerId': 'law-1',
            'lawyerName': 'Mona Fahmy',
            'rating': 4,
            'comment': 'Helpful',
          },
        ]),
        'reviews/r-1': {'success': true, 'data': {'id': 'r-1'}},
      });
      await _pump(tester, api, const ReviewsScreen());
      expect(find.textContaining('For Mona Fahmy'), findsOneWidget);

      await tester.tap(find.byTooltip('Moderate review'));
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('review-moderation-save'));
      expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
      expect(find.textContaining('not recalculated'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('review-comment')), 'Edited comment');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(api.lastBodyFor('PUT', 'reviews/r-1'), {'comment': 'Edited comment'});
    });
  });

  group('identity enrichment via permitted columns', () {
    test('bookings gain client name/email from users(id,name,email)', () async {
      final requests = <http.Request>[];
      final api = _service((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/bookings') {
          return _json([
            {'id': 'b-1', 'user_id': 'u-1', 'lawyer_id': 'law-1', 'status': 'Pending'},
            {'id': 'b-2', 'user_id': 'u-1', 'lawyer_id': 'law-1', 'status': 'Pending'},
          ], 200, headers: {'content-range': '0-1/2'});
        }
        return _json([
          {'id': 'u-1', 'name': 'Sara Ali', 'email': 'sara@example.com'},
        ], 200);
      });
      final res = await api.get('bookings', query: {'page': '1', 'limit': '100'});
      final users = requests.singleWhere((r) => r.url.path == '/rest/v1/users');
      expect(users.url.queryParameters['select'], 'id,name,email');
      expect(users.url.queryParameters['id'], 'in.(u-1)');
      final items = itemsOf(res);
      expect(items.first['userName'], 'Sara Ali');
      expect(Booking.fromJson(items.first).clientLabel, 'Sara Ali (sara@example.com)');
      expect(listPageOf(res)['total'], 2);
    });

    test('reviews gain lawyer names but no reviewer identity', () async {
      final requests = <http.Request>[];
      final api = _service((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/public_reviews') {
          return _json([
            {'id': 'r-1', 'user_name': 'Sara', 'lawyer_id': 'law-1', 'rating': 5},
          ], 200, headers: {'content-range': '0-0/1'});
        }
        return _json([{'id': 'law-1', 'name': 'Mona Fahmy'}], 200);
      });
      final res = await api.get('reviews', query: {'page': '1', 'limit': '100'});
      final lawyers = requests.singleWhere((r) => r.url.path == '/rest/v1/lawyers');
      expect(lawyers.url.queryParameters['select'], 'id,name');
      final review = itemsOf(res).single;
      expect(review['lawyerName'], 'Mona Fahmy');
      expect(review.containsKey('userId'), isFalse);
      expect(requests.any((r) => r.url.path == '/rest/v1/users'), isFalse);
    });

    test('lookups are skipped for empty pages and unsafe ids', () async {
      final paths = <String>[];
      final api = _service((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/rest/v1/notifications') {
          return _json([
            {'id': 'n-1', 'user_id': 'bad id,with)chars', 'title': 'Hi'},
          ], 200);
        }
        return _json([], 200);
      });
      await api.get('subscriptions', query: {'page': '1'});
      await api.get('notifications', query: {'page': '1'});
      expect(paths, ['/rest/v1/subscriptions', '/rest/v1/notifications']);
    });

    test('a denied lookup leaves the list usable', () async {
      final api = _service((request) async {
        if (request.url.path == '/rest/v1/subscriptions') {
          return _json([
            {'id': 's-1', 'user_id': 'u-1', 'plan_title': 'Gold', 'start_date': '2026-01-01T00:00:00Z'},
          ], 200);
        }
        return _json({'code': '42501', 'message': 'permission denied for table users'}, 403);
      });
      final res = await api.get('subscriptions', query: {'page': '1'});
      final sub = Subscription.fromJson(itemsOf(res).single);
      expect(sub.userLabel, contains('u-1'));
      expect(sub.startDate, DateTime.utc(2026, 1, 1));
    });

    test('chats are paged with an exact total instead of a capped list', () async {
      late http.Request captured;
      final api = _service((request) async {
        captured = request;
        return _json([{'id': 'c-1'}], 200, headers: {'content-range': '100-100/101'});
      });
      final res = await api.get('chats', query: {'page': '2', 'limit': '100'});
      expect(captured.url.queryParameters['offset'], '100');
      expect(captured.headers['Prefer'], contains('count=exact'));
      expect(listPageOf(res)['total'], 101);
      expect(listPageOf(res)['totalPages'], 2);
    });
  });
}
