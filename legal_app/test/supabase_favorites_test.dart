import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legalserviceapp/services/api_client.dart';
import 'package:legalserviceapp/services/app_repository.dart';

void main() {
  group('authenticated Supabase favorites slice', () {
    test('reads only the session owner and joins public lawyer data', () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/favorites') {
            return http.Response(
              jsonEncode(<Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'favorite-1',
                  'user_id': 'profile-1',
                  'lawyer_id': 'lawyer-1',
                  'created_at': '2026-10-23T12:00:00Z',
                },
              ]),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/rest/v1/lawyers') {
            return http.Response(
              jsonEncode(<Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'lawyer-1',
                  'name': 'Nour Hassan',
                  'specialty': 'Family law',
                  'price': 'EGP 1,000 / hour',
                  'price_value': 1000,
                  'rating': 4.8,
                  'location': 'Sohag',
                },
              ]),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response('unexpected request', 500);
        }),
        idTokenProvider: () async => 'session-jwt',
        currentUidProvider: () => 'profile-1',
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseFavorites: true,
      );
      addTearDown(api.dispose);

      final entries = await AppRepository(api).fetchMyFavorites();

      expect(entries, hasLength(1));
      expect(entries.single.favoriteId, 'favorite-1');
      expect(entries.single.lawyer.id, 'lawyer-1');
      expect(entries.single.lawyer.name, 'Nour Hassan');
      expect(requests, hasLength(2));

      final favoritesRequest = requests.first;
      expect(favoritesRequest.method, 'GET');
      expect(favoritesRequest.url.path, '/rest/v1/favorites');
      expect(favoritesRequest.url.queryParameters['select'], 'id,lawyer_id,created_at');
      expect(favoritesRequest.url.queryParameters['order'], 'created_at.desc');
      expect(favoritesRequest.url.queryParameters.containsKey('user_id'), isFalse,
          reason: 'RLS, not a caller-controlled owner filter, scopes the query');
      expect(favoritesRequest.headers['apikey'], 'public-test-key');
      expect(favoritesRequest.headers['Authorization'], 'Bearer session-jwt');

      final lawyerRequest = requests.last;
      expect(lawyerRequest.url.path, '/rest/v1/lawyers');
      expect(lawyerRequest.url.queryParameters['id'], 'eq.lawyer-1');
      expect(lawyerRequest.url.queryParameters['select'], isNot(contains('user_id')));
      expect(lawyerRequest.headers['apikey'], 'public-test-key');
      expect(lawyerRequest.headers.containsKey('Authorization'), isFalse,
          reason: 'lawyer cards use the public, minimal-column catalogue read');
    });

    test('adds with the authenticated RPC and never sends an owner ID', () async {
      late http.Request request;
      final api = ApiClient(
        client: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'id': 'favorite-1',
              'user_id': 'profile-1',
              'lawyer_id': 'lawyer-1',
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
        idTokenProvider: () async => 'session-jwt',
        currentUidProvider: () => 'profile-1',
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseFavorites: true,
      );
      addTearDown(api.dispose);

      final favoriteId = await AppRepository(api).addFavorite(' lawyer-1 ');

      expect(favoriteId, 'favorite-1');
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/rpc_favorite_add');
      expect(jsonDecode(request.body), <String, dynamic>{'p_lawyer_id': 'lawyer-1'});
      expect(request.headers['apikey'], 'public-test-key');
      expect(request.headers['Authorization'], 'Bearer session-jwt');
    });

    test('deletes by favorite ID and relies on RLS for owner authorization', () async {
      late http.Request request;
      final api = ApiClient(
        client: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{'id': 'favorite-1'},
            ]),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
        idTokenProvider: () async => 'session-jwt',
        currentUidProvider: () => 'profile-1',
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseFavorites: true,
      );
      addTearDown(api.dispose);

      await AppRepository(api).removeFavorite('favorite-1');

      expect(request.method, 'DELETE');
      expect(request.url.path, '/rest/v1/favorites');
      expect(request.url.queryParameters['id'], 'eq.favorite-1');
      expect(request.url.queryParameters.containsKey('user_id'), isFalse);
      expect(request.headers['Prefer'], 'return=representation');
      expect(request.headers['Authorization'], 'Bearer session-jwt');
    });

    test('rejects a caller-selected different owner before making a request',
        () async {
      var calls = 0;
      final api = ApiClient(
        client: MockClient((_) async {
          calls++;
          return http.Response('[]', 200);
        }),
        idTokenProvider: () async => 'session-jwt',
        currentUidProvider: () => 'profile-1',
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseFavorites: true,
      );
      addTearDown(api.dispose);

      await expectLater(
        AppRepository(api).fetchFavorites('profile-2'),
        throwsA(isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)),
      );
      expect(calls, 0);
    });

    test('keeps the migration flag disabled by default', () {
      final api = ApiClient(
        currentUidProvider: () => 'profile-1',
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
      );
      addTearDown(api.dispose);

      expect(api.usesSupabaseFavorites, isFalse);
    });

    test('rejects an RLS-filtered delete that returned no row', () async {
      final api = ApiClient(
        client: MockClient((_) async => http.Response('[]', 200)),
        idTokenProvider: () async => 'session-jwt',
        currentUidProvider: () => 'profile-1',
        supabaseUrl: 'https://project.example.test',
        supabaseAnonKey: 'public-test-key',
        enableSupabaseFavorites: true,
      );
      addTearDown(api.dispose);

      await expectLater(
        AppRepository(api).removeFavorite('favorite-from-another-owner'),
        throwsA(isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 404)),
      );
    });
  });
}
