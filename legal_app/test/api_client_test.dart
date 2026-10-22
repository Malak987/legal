import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legalserviceapp/services/api_client.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('base URL', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('the Android emulator gets the host alias, never localhost', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(ApiClient.defaultBaseUrl, 'http://10.0.2.2:5000/api');
    });

    test('other platforms default to localhost', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(ApiClient.defaultBaseUrl, 'http://localhost:5000/api');
    });

    test('an explicit base URL always wins', () {
      final client = ApiClient(
        baseUrl: 'http://192.168.1.10:5000/api',
        client: MockClient((_) async => jsonOk(const {})),
        currentUidProvider: () => null,
      );
      expect(client.baseUrl, 'http://192.168.1.10:5000/api');
    });
  });

  group('requests', () {
    test('sends the bearer token and the full path', () async {
      Uri? seen;
      String? authorization;
      final api = testApiClient(handler: (request, _) async {
        seen = request.url;
        authorization = request.headers['Authorization'];
        return jsonOk({'id': 'uid-1', 'name': 'Sara'});
      });

      await api.get('users/uid-1');

      expect(seen.toString(), 'http://test.local/api/users/uid-1');
      expect(authorization, 'Bearer test-token');
    });

    test('a leading slash does not double the separator', () async {
      Uri? seen;
      final api = testApiClient(handler: (request, _) async {
        seen = request.url;
        return jsonOk(const []);
      });

      await api.get('/cases');

      expect(seen.toString(), 'http://test.local/api/cases');
    });

    test('query parameters are encoded', () async {
      Uri? seen;
      final api = testApiClient(handler: (request, _) async {
        seen = request.url;
        return jsonOk({'items': <dynamic>[]});
      });

      await api.get('lawyers', query: {'search': 'family law', 'limit': '5'});

      expect(seen!.queryParameters['search'], 'family law');
      expect(seen!.queryParameters['limit'], '5');
    });

    test('POST bodies are JSON and the envelope is unwrapped', () async {
      Map<String, dynamic>? body;
      final api = testApiClient(handler: (request, _) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonOk({'id': 'uid-1', 'name': 'Sara'}, status: 201);
      });

      final data = await api.post('users/me', body: {'name': 'Sara'});

      expect(body, {'name': 'Sara'});
      expect(data, {'id': 'uid-1', 'name': 'Sara'});
    });

    test('a 401 is retried once with a refreshed token', () async {
      var tokenCalls = 0;
      var requestCalls = 0;
      final api = ApiClient(
        baseUrl: 'http://test.local/api',
        client: MockClient((request) async {
          requestCalls++;
          if (request.headers['Authorization'] == 'Bearer fresh') {
            return jsonOk({'id': 'uid-1', 'name': 'Sara'});
          }
          return jsonError(401, 'Unauthorized');
        }),
        // The second read is the forced refresh.
        idTokenProvider: () async => ++tokenCalls == 1 ? 'stale' : 'fresh',
        currentUidProvider: () => 'uid-1',
      );

      final data = await api.get('users/uid-1');

      expect(requestCalls, 2);
      expect(tokenCalls, 2);
      expect(data, {'id': 'uid-1', 'name': 'Sara'});
    });

    test('a second 401 surfaces as an error, not another retry', () async {
      var calls = 0;
      final api = testApiClient(handler: (_, __) async {
        calls++;
        return jsonError(401, 'Unauthorized');
      });

      await expectLater(
        api.get('users/uid-1'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 401)
            .having((e) => e.isUnauthorized, 'isUnauthorized', true)),
      );
      expect(calls, 2);
    });

    test('an error envelope keeps the server message and status', () async {
      final api = testApiClient(
        handler: (_, __) async =>
            jsonError(409, 'A profile already exists for this account.'),
      );

      await expectLater(
        api.post('users/me', body: {'name': 'Sara'}),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message',
                'A profile already exists for this account.')
            .having((e) => e.isConflict, 'isConflict', true)),
      );
    });

    test('a request that never answers fails instead of hanging forever',
        () async {
      final api = testApiClient(
        // Longer than the deadline configured below.
        handler: (_, __) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return jsonOk(profileJson());
        },
        requestTimeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        api.get('users/uid-1'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 0)
            .having((e) => e.isTransient, 'isTransient', true)
            .having((e) => e.message, 'message', contains('took too long'))),
      );

      // Let the abandoned handler finish so no timer outlives the test.
      await Future<void>.delayed(const Duration(milliseconds: 220));
    });

    test('a non-JSON body becomes an ApiException, not a FormatException',
        () async {
      final api = testApiClient(
        handler: (_, __) async => http.Response('<html>oops</html>', 502),
      );

      await expectLater(
        api.get('cases'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 502)
            .having((e) => e.isTransient, 'isTransient', true)),
      );
    });
  });

  group('profiles', () {
    test('getMyProfile parses the current uid document', () async {
      Uri? seen;
      final api = testApiClient(handler: (request, _) async {
        seen = request.url;
        return jsonOk(profileJson(name: 'Nour', role: 'lawyer'));
      });

      final profile = await api.getMyProfile();

      expect(seen!.path, '/api/users/uid-1');
      expect(profile.uid, 'uid-1');
      expect(profile.name, 'Nour');
      expect(profile.role, 'lawyer');
      expect(profile.isAdmin, isFalse);
    });

    test('getMyProfile refuses to run without a session', () async {
      final api = ApiClient(
        baseUrl: 'http://test.local/api',
        client: MockClient((_) async => jsonOk(const {})),
        currentUidProvider: () => null,
      );

      await expectLater(
        api.getMyProfile(),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 401)),
      );
    });

    test('refuses a document that is not the current uid', () async {
      // A response for another account must never stand in as this session's
      // profile, even though the backend should never route it here.
      final api = testApiClient(
        handler: (_, __) async => jsonOk(profileJson(id: 'someone-else')),
      );

      await expectLater(
        api.getMyProfile(),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 0)
            .having((e) => e.isTransient, 'isTransient', true)),
      );
    });

    test('a 409 alone is not proof a profile exists', () async {
      // "already exists" only counts once the profile is actually read back.
      final api = testApiClient(handler: (request, _) async {
        if (request.method == 'POST') {
          return jsonError(409, 'A profile already exists for this account.');
        }
        return jsonError(404, 'User not found');
      });

      await expectLater(
        api.provisionProfile(name: 'Sara'),
        throwsA(isA<ApiException>()
            .having((e) => e.isNotFound, 'isNotFound', true)),
      );
    });

    test('a missing profile is reported as 404 so callers can provision', () {
      expect(
        ApiException('User not found', 404).isNotFound,
        isTrue,
      );
    });

    test('provisioning treats 409 as "already provisioned" and reads back',
        () async {
      final calls = <String>[];
      final api = testApiClient(handler: (request, _) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'POST') {
          return jsonError(409, 'A profile already exists for this account.');
        }
        return jsonOk(profileJson(name: 'Existing'));
      });

      final profile = await api.provisionProfile(name: 'Typed Name');

      expect(calls, ['POST /api/users/me', 'GET /api/users/uid-1']);
      // The stored profile is returned untouched — no rename happened.
      expect(profile.name, 'Existing');
    });

    test('provisioning sends only the name, never a role or uid', () async {
      Map<String, dynamic>? body;
      final api = testApiClient(handler: (request, _) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonOk(profileJson());
      });

      await api.provisionProfile(name: '  Sara Ali  ');

      expect(body, {'name': 'Sara Ali'});
    });

    test('updateMyProfile targets the signed-in uid and sends no role',
        () async {
      String? method;
      Uri? seen;
      Map<String, dynamic>? body;
      final api = testApiClient(handler: (request, _) async {
        method = request.method;
        seen = request.url;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonOk(profileJson(name: 'New Name'));
      });

      await api.updateMyProfile(
        name: 'New Name',
        email: 'sara@example.com',
        phone: '0100',
      );

      expect(method, 'PUT');
      expect(seen!.path, '/api/users/uid-1');
      expect(body!.containsKey('role'), isFalse);
      expect(body!['name'], 'New Name');
      expect(body!['email'], 'sara@example.com');
    });
  });
}
