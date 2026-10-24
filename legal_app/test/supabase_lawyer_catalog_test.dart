import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legalserviceapp/services/api_client.dart';
import 'package:legalserviceapp/services/app_repository.dart';

void main() {
  group('public lawyer catalogue Supabase slice', () {
    test('uses anonymous PostgREST, server filters, and snake-case row mapping',
        () async {
      final requests = <http.Request>[];
      var tokenReads = 0;
      final api = ApiClient(
        baseUrl: 'https://legacy.example.test/api',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'lawyer-1',
                'category_id': 'family-category',
                'name': 'Nour Hassan',
                'specialty': 'Family law',
                'price': 'EGP 1,000 / hour',
                'price_value': 1000,
                'image': 'lawyer.png',
                'rating': 4.8,
                'location': 'Sohag',
                'experience': '12 years',
                'bio': 'Family and civil matters',
                'is_popular': true,
                'is_top': false,
              },
            ]),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
        idTokenProvider: () async {
          tokenReads++;
          return 'must-not-be-used';
        },
        currentUidProvider: () => null,
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseLawyerCatalog: true,
      );
      addTearDown(api.dispose);

      final lawyers = await AppRepository(api).fetchLawyers(
        search: 'Family, Law) %* الأسرة',
        isPopular: true,
        isTop: false,
      );

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.origin, 'https://project.example.test');
      expect(request.url.path, '/rest/v1/lawyers');
      expect(request.headers['apikey'], 'public-test-key');
      expect(request.headers['Prefer'], 'count=exact');
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(
        request.url.queryParameters['select'],
        'id,category_id,name,specialty,price,price_value,image,rating,location,experience,bio,is_popular,is_top',
      );
      expect(request.url.queryParameters['select'], isNot(contains('user_id')));
      expect(request.url.queryParameters['order'], 'rating.desc');
      expect(request.url.queryParameters['limit'], '100');
      expect(request.url.queryParameters['offset'], '0');
      expect(
        request.url.queryParameters['or'],
        '(name.ilike.*Family Law الأسرة*,specialty.ilike.*Family Law الأسرة*,location.ilike.*Family Law الأسرة*)',
      );
      expect(request.url.queryParameters['is_popular'], 'eq.true');
      expect(request.url.queryParameters['is_top'], 'eq.false');
      expect(tokenReads, 0, 'public catalogue access must not depend on a user session');

      expect(lawyers, hasLength(1));
      final lawyer = lawyers.single;
      expect(lawyer.id, 'lawyer-1');
      expect(lawyer.name, 'Nour Hassan');
      expect(lawyer.categoryId, 'family-category');
      expect(lawyer.priceValue, 1000);
      expect(lawyer.experience, '12 years');
      expect(lawyer.userId, isNull);
      expect(lawyer.isPopular, isTrue);
      expect(lawyer.isTop, isFalse);
    });

    test('filters PostgREST lawyer results by the selected category', () async {
      late http.Request request;
      final api = ApiClient(
        client: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'lawyer-1',
                'category_id': 'family-category',
                'name': 'Nour Hassan',
              },
            ]),
            200,
            headers: <String, String>{
              'content-type': 'application/json',
              'content-range': '0-0/1',
            },
          );
        }),
        currentUidProvider: () => null,
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseLawyerCatalog: true,
      );
      addTearDown(api.dispose);

      final page = await AppRepository(api).fetchLawyerPage(
        categoryId: 'family-category',
      );

      expect(request.url.path, '/rest/v1/lawyers');
      expect(request.url.queryParameters['category_id'], 'eq.family-category');
      expect(page.items.single.categoryId, 'family-category');
    });

    test('pages PostgREST results and reads the exact total from Content-Range',
        () async {
      late http.Request request;
      final api = ApiClient(
        client: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'lawyer-3',
                'name': 'Mona Ali',
                'price': 'EGP 700 / hour',
                'rating': 4.7,
                'is_popular': true,
                'is_top': false,
              },
              <String, dynamic>{
                'id': 'lawyer-4',
                'name': 'Hany Saleh',
                'price': 'EGP 600 / hour',
                'rating': 4.6,
                'is_popular': true,
                'is_top': false,
              },
            ]),
            200,
            headers: <String, String>{
              'content-type': 'application/json',
              'content-range': '2-3/5',
            },
          );
        }),
        currentUidProvider: () => null,
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseLawyerCatalog: true,
      );
      addTearDown(api.dispose);

      final page = await AppRepository(api).fetchLawyerPage(
        search: 'Mona Ali',
        isPopular: true,
        isTop: false,
        page: 2,
        limit: 2,
      );

      expect(request.url.queryParameters['limit'], '2');
      expect(request.url.queryParameters['offset'], '2');
      expect(request.url.queryParameters['is_popular'], 'eq.true');
      expect(request.url.queryParameters['is_top'], 'eq.false');
      expect(request.url.queryParameters['or'], contains('Mona Ali'));
      expect(page.items.map((lawyer) => lawyer.id), ['lawyer-3', 'lawyer-4']);
      expect(page.page, 2);
      expect(page.limit, 2);
      expect(page.total, 5);
      expect(page.totalPages, 3);
      expect(page.hasMore, isTrue);
    });

    test('uses public PostgREST for detail and returns null for a missing row',
        () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'https://legacy.example.test/api',
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.queryParameters['id'] == 'eq.lawyer-404') {
            return http.Response('[]', 200);
          }
          return http.Response(
            jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'lawyer-1',
                'name': 'Nour Hassan',
                'price': 'EGP 1,000 / hour',
                'price_value': 1000,
              },
            ]),
            200,
          );
        }),
        currentUidProvider: () => null,
        supabaseUrl: 'https://project.example.test/',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseLawyerCatalog: true,
      );
      addTearDown(api.dispose);
      final repository = AppRepository(api);

      final lawyer = await repository.fetchLawyer('lawyer-1');
      final missingLawyer = await repository.fetchLawyer('lawyer-404');

      expect(lawyer?.id, 'lawyer-1');
      expect(lawyer?.name, 'Nour Hassan');
      expect(lawyer?.priceValue, 1000);
      expect(missingLawyer, isNull);
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.url.path, '/rest/v1/lawyers');
        expect(request.url.queryParameters['limit'], '1');
        expect(request.headers['apikey'], 'public-test-key');
        expect(request.headers.containsKey('Authorization'), isFalse);
      }
      expect(requests.first.url.queryParameters['id'], 'eq.lawyer-1');
      expect(requests.last.url.queryParameters['id'], 'eq.lawyer-404');
    });

    test('normalizes malformed catalogue payloads to typed invalid-response errors',
        () async {
      final api = ApiClient(
        client: MockClient((_) async => http.Response(
              jsonEncode(<String, dynamic>{'unexpected': true}),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            )),
        currentUidProvider: () => null,
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseLawyerCatalog: true,
      );
      addTearDown(api.dispose);

      await expectLater(
        AppRepository(api).fetchLawyers(),
        throwsA(isA<ApiException>()
            .having((error) => error.kind, 'kind', ApiErrorKind.invalidResponse)),
      );
    });

    test('rejects malformed typed lawyer fields instead of coercing them',
        () async {
      final api = ApiClient(
        client: MockClient((_) async => http.Response(
              jsonEncode(<Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'lawyer-invalid',
                  'name': 'Not A Number Rating',
                  'rating': 'excellent',
                },
              ]),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            )),
        currentUidProvider: () => null,
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseLawyerCatalog: true,
      );
      addTearDown(api.dispose);

      await expectLater(
        AppRepository(api).fetchLawyers(),
        throwsA(isA<ApiException>()
            .having((error) => error.kind, 'kind', ApiErrorKind.invalidResponse)),
      );
    });

    test('normalizes transport failures to retryable network errors', () async {
      final api = ApiClient(
        client: MockClient((_) async {
          throw http.ClientException('connection refused');
        }),
        currentUidProvider: () => null,
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseLawyerCatalog: true,
      );
      addTearDown(api.dispose);

      await expectLater(
        AppRepository(api).fetchLawyers(),
        throwsA(isA<ApiException>()
            .having((error) => error.kind, 'kind', ApiErrorKind.network)
            .having((error) => error.isTransient, 'isTransient', isTrue)),
      );
    });

    test('rejects unsafe lawyer IDs before sending a PostgREST filter', () async {
      var requests = 0;
      final api = ApiClient(
        client: MockClient((_) async {
          requests++;
          return http.Response('[]', 200);
        }),
        currentUidProvider: () => null,
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseLawyerCatalog: true,
      );
      addTearDown(api.dispose);

      await expectLater(
        AppRepository(api).fetchLawyer('lawyer,or(id.eq.*)'),
        throwsA(isA<ApiException>()
            .having((error) => error.statusCode, 'status', 400)),
      );
      expect(requests, 0);
    });

    test('does not hide PostgREST authorization failures behind Express fallback',
        () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'https://legacy.example.test/api',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, dynamic>{'message': 'permission denied'}),
            403,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
        currentUidProvider: () => null,
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseLawyerCatalog: true,
      );
      addTearDown(api.dispose);

      await expectLater(
        AppRepository(api).fetchLawyers(),
        throwsA(isA<ApiException>()
            .having((error) => error.statusCode, 'status', 403)
            .having((error) => error.kind, 'kind', ApiErrorKind.forbidden)
            .having((error) => error.message, 'message', 'permission denied')),
      );
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/rest/v1/lawyers');
    });

    test('keeps Supabase-backed catalogues disabled without explicit opt-in',
        () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'https://legacy.example.test/api',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{'items': <Map<String, dynamic>>[]},
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
        currentUidProvider: () => null,
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseLawyerCatalog: false,
      );
      addTearDown(api.dispose);

      await AppRepository(api).fetchLawyers();

      expect(requests, hasLength(1));
      expect(requests.single.url.origin, 'https://legacy.example.test');
      expect(requests.single.url.path, '/api/lawyers');
    });

    test('retains an explicit Express compatibility path without Supabase config',
        () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'https://legacy.example.test/api',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'legacy-lawyer',
                    'name': 'Legacy Lawyer',
                    'price': 'EGP 500 / hour',
                  },
                ],
              },
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
        currentUidProvider: () => null,
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: '',
      );
      addTearDown(api.dispose);

      final lawyers = await AppRepository(api).fetchLawyers();

      expect(requests, hasLength(1));
      expect(requests.single.url.origin, 'https://legacy.example.test');
      expect(requests.single.url.path, '/api/lawyers');
      expect(requests.single.url.queryParameters['page'], '1');
      expect(requests.single.url.queryParameters['limit'], '100');
      expect(lawyers.single.id, 'legacy-lawyer');
    });
  });
}
