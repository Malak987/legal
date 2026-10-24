import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legalserviceapp/services/api_client.dart';
import 'package:legalserviceapp/services/app_repository.dart';

void main() {
  group('legal category repository', () {
    test('loads public categories through the API and validates the response',
        () async {
      late http.Request request;
      final api = ApiClient(
        baseUrl: 'https://api.example.test/api',
        client: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'message': 'Categories loaded',
              'data': <String, dynamic>{
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'family-law',
                    'name': 'Family law',
                    'slug': 'family-law',
                  },
                ],
              },
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
        currentUidProvider: () => null,
      );
      addTearDown(api.dispose);

      final categories = await AppRepository(api).fetchCategories(search: 'family');

      expect(request.method, 'GET');
      expect(request.url.path, '/api/categories');
      expect(request.url.queryParameters, <String, String>{
        'page': '1',
        'limit': '100',
        'search': 'family',
      });
      expect(categories, hasLength(1));
      expect(categories.single.id, 'family-law');
      expect(categories.single.name, 'Family law');
      expect(categories.single.slug, 'family-law');
    });

    test('sends category selection to the legacy lawyer listing endpoint',
        () async {
      late http.Request request;
      final api = ApiClient(
        baseUrl: 'https://api.example.test/api',
        client: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'message': 'Lawyers loaded',
              'data': <String, dynamic>{
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'lawyer-1',
                    'category_id': 'family-law',
                    'name': 'Nour Hassan',
                  },
                ],
                'page': 1,
                'limit': 20,
                'total': 1,
                'totalPages': 1,
              },
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
        currentUidProvider: () => null,
      );
      addTearDown(api.dispose);

      final page = await AppRepository(api).fetchLawyerPage(
        categoryId: 'family-law',
      );

      expect(request.url.path, '/api/lawyers');
      expect(request.url.queryParameters['categoryId'], 'family-law');
      expect(page.items.single.categoryId, 'family-law');
    });

    test('rejects malformed category list responses', () async {
      final api = ApiClient(
        baseUrl: 'https://api.example.test/api',
        client: MockClient((_) async => http.Response(
              jsonEncode(<String, dynamic>{
                'success': true,
                'data': <String, dynamic>{'items': 'not-a-list'},
              }),
              200,
            )),
        currentUidProvider: () => null,
      );
      addTearDown(api.dispose);

      await expectLater(
        AppRepository(api).fetchCategories(),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
