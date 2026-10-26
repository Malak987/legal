// Regression tests for three admin-panel Supabase runtime failures:
//   1. POST /rest/v1/rpc/rpc_admin_lawyers_page  -> 404 (PGRST202)
//   2. POST /rest/v1/legal_categories?select=*   -> 400
//   3. GET  /rest/v1/public_reviews?...          -> 404 (PGRST205)
//
// Each test exercises the real ApiService over a mock HTTP client and checks
// the exact request against the SQL contract declared in supabase/migrations,
// so client/schema drift is caught without a live database.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legal_admin/services/api_service.dart';

const _base = 'https://example.supabase.co';
final _migrationsDir = Directory('../supabase/migrations');

String _migration(String fileName) =>
    File('${_migrationsDir.path}/$fileName').readAsStringSync();

ApiService _service(Future<http.Response> Function(http.Request) handler) {
  return ApiService(
    client: MockClient(handler),
    tokenProvider: () async => 'test-user-jwt',
    supabaseUrl: _base,
    supabaseAnonKey: 'test-anon-key',
  );
}

http.Response _json(Object body, int status, {Map<String, String>? headers}) =>
    http.Response(jsonEncode(body), status, headers: {
      'content-type': 'application/json',
      ...?headers,
    });

/// Parses `name type DEFAULT ...` parameters from a CREATE FUNCTION header.
Map<String, String> _functionParams(String sql, String qualifiedName) {
  final match = RegExp(
    'CREATE OR REPLACE FUNCTION ${RegExp.escape(qualifiedName)}\\(([\\s\\S]*?)\\)\\s*RETURNS',
  ).firstMatch(sql);
  expect(match, isNotNull, reason: '$qualifiedName must be defined in the migration');
  final params = <String, String>{};
  for (final raw in match!.group(1)!.split(',')) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) params[parts[0]] = parts[1].toLowerCase();
  }
  return params;
}

void main() {
  group('1. rpc_admin_lawyers_page (observed HTTP 404)', () {
    test('request uses exactly the named arguments declared by the migration', () async {
      late http.Request captured;
      final api = _service((request) async {
        captured = request;
        return _json(
          {'items': [], 'page': 1, 'limit': 100, 'total': 0, 'totalPages': 1},
          200,
        );
      });

      await api.get('lawyers', query: {'page': '1', 'limit': '$kMaxPageSize'});

      expect(captured.method, 'POST');
      expect(captured.url.path, '/rest/v1/rpc/rpc_admin_lawyers_page');
      expect(captured.headers['Authorization'], 'Bearer test-user-jwt');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;

      final params = _functionParams(
        _migration('20261025144000_admin_native_workflows.sql'),
        'public.rpc_admin_lawyers_page',
      );
      // PostgREST resolves RPCs by argument *names*; any mismatch is a 404.
      expect(body.keys.toSet(), params.keys.toSet());
      expect(params, {
        'p_page': 'integer',
        'p_limit': 'integer',
        'p_search': 'text',
        'p_category_id': 'text',
        'p_is_popular': 'boolean',
        'p_is_top': 'boolean',
      });
      expect(body['p_page'], 1);
      expect(body['p_limit'], kMaxPageSize);
    });

    test('the defining migration grants EXECUTE to authenticated only', () {
      final sql = _migration('20261025144000_admin_native_workflows.sql');
      expect(
        sql,
        contains(
          'GRANT EXECUTE ON FUNCTION public.rpc_admin_lawyers_page(integer, integer, text, text, boolean, boolean)\n  TO authenticated;',
        ),
      );
      expect(sql, contains('FROM PUBLIC, anon, service_role;'));
    });

    test('a missing function surfaces the PostgREST code (PGRST202)', () async {
      final api = _service((_) async => _json({
            'code': 'PGRST202',
            'details': 'Searched for the function public.rpc_admin_lawyers_page ...',
            'hint': null,
            'message': 'Could not find the function public.rpc_admin_lawyers_page'
                '(p_category_id, p_is_popular, p_is_top, p_limit, p_page, p_search) in the schema cache',
          }, 404));

      await expectLater(
        api.get('lawyers', query: {'page': '1', 'limit': '100'}),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.code, 'code', 'PGRST202')
            .having((e) => e.message, 'message', contains('rpc_admin_lawyers_page'))),
      );
    });
  });

  group('2. legal_categories insert (observed HTTP 400)', () {
    final createTable = RegExp(
      r'CREATE TABLE public\.legal_categories \(([\s\S]*?)\n\);',
    ).firstMatch(_migration('20261024102004_legal_categories_and_assignments.sql'));

    Set<String> tableColumns() {
      expect(createTable, isNotNull);
      return createTable!
          .group(1)!
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('CONSTRAINT') && !line.startsWith('CHECK'))
          .map((line) => line.split(RegExp(r'\s+')).first)
          .toSet();
    }

    test('slug is declared NOT NULL without a default, so it must be sent', () {
      final body = createTable!.group(1);
      expect(body, contains('slug text NOT NULL,'));
      expect(body, isNot(contains('slug text NOT NULL DEFAULT')));
    });

    Future<Map<String, dynamic>> captureInsert(String name) async {
      late http.Request captured;
      final api = _service((request) async {
        captured = request;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json([
          {'id': 'new-id', ...body, 'created_at': 'now', 'updated_at': 'now'},
        ], 201);
      });
      await api.post('categories', body: {'name': name});
      expect(captured.method, 'POST');
      expect(captured.url.path, '/rest/v1/legal_categories');
      expect(captured.url.queryParameters, {'select': '*'});
      expect(captured.headers['Prefer'], 'return=representation');
      return jsonDecode(captured.body) as Map<String, dynamic>;
    }

    test('sends only name + a non-empty slug, all of which exist and are grantable', () async {
      final body = await captureInsert('Estate Law');
      expect(body, {'name': 'Estate Law', 'slug': 'estate-law'});
      // Unknown columns are rejected by PostgREST with 400 (PGRST204).
      expect(tableColumns(), containsAll(body.keys));
      // 20261025143000 narrows the authenticated grant to INSERT (name, slug).
      expect(
        _migration('20261025143000_supabase_native_workflows.sql'),
        contains('GRANT INSERT (name, slug), UPDATE (name, slug), DELETE'),
      );
    });

    test('non-Latin names get a unique slug instead of a colliding constant', () async {
      final first = await captureInsert('قانون الأسرة');
      final second = await captureInsert('القانون الجنائي');
      final slugPattern = RegExp(r'^category-[0-9a-z]{10}$');
      expect(first['slug'], matches(slugPattern));
      expect(second['slug'], matches(slugPattern));
      expect(first['slug'], isNot(second['slug']));
      expect(first['name'], 'قانون الأسرة');
    });

    test('a 400 keeps the PostgreSQL error code, message and details', () async {
      final api = _service((_) async => _json({
            'code': '23502',
            'details': 'Failing row contains (...).',
            'hint': null,
            'message': 'null value in column "slug" of relation "legal_categories" violates not-null constraint',
          }, 400));

      await expectLater(
        api.post('categories', body: {'name': 'Estate Law'}),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.code, 'code', '23502')
            .having((e) => e.details, 'details', 'Failing row contains (...).')
            .having((e) => e.toString(), 'toString', contains('"slug"'))),
      );
    });
  });

  group('3. public_reviews read (observed HTTP 404)', () {
    final viewMatch = RegExp(
      r'CREATE OR REPLACE VIEW public\.public_reviews\s+WITH \(([^)]*)\)\s+AS\s+SELECT ([\s\S]*?)\s+FROM public\.reviews;',
    ).firstMatch(_migration('20261025140000_supabase_security_storage.sql'));

    test('the client selects only columns the privacy-preserving view exposes', () async {
      late http.Request captured;
      final api = _service((request) async {
        captured = request;
        return _json([], 200, headers: {'content-range': '*/0'});
      });

      await api.get('reviews', query: {'page': '1', 'limit': '$kMaxPageSize'});

      expect(captured.method, 'GET');
      expect(captured.url.path, '/rest/v1/public_reviews');
      expect(captured.url.queryParameters, {
        'select': 'id,user_name,lawyer_id,rating,comment,created_at,updated_at',
        'order': 'created_at.desc',
        'limit': '100',
        'offset': '0',
      });

      expect(viewMatch, isNotNull, reason: 'public_reviews must be defined by a migration');
      final viewColumns =
          viewMatch!.group(2)!.split(',').map((c) => c.trim()).toSet();
      final requested = captured.url.queryParameters['select']!.split(',').toSet();
      expect(viewColumns, containsAll(requested));
      expect(viewColumns, isNot(contains('user_id')));
      expect(requested, isNot(contains('user_id')));
    });

    test('the view stays subject to reviews RLS (security_invoker)', () {
      expect(viewMatch!.group(1), contains('security_invoker = true'));
      expect(
        _migration('20261025140000_supabase_security_storage.sql'),
        contains('GRANT SELECT ON public.public_reviews TO anon, authenticated;'),
      );
    });

    test('a missing relation surfaces the PostgREST code (PGRST205)', () async {
      final api = _service((_) async => _json({
            'code': 'PGRST205',
            'details': null,
            'hint': null,
            'message': "Could not find the table 'public.public_reviews' in the schema cache",
          }, 404));

      await expectLater(
        api.get('reviews', query: {'page': '1', 'limit': '100'}),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.code, 'code', 'PGRST205')
            .having((e) => e.details, 'details', isNull)),
      );
    });
  });
}
