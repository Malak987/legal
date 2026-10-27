import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:math' show Random;

import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';

/// Supabase-only data adapter for the admin panel.
///
/// Reads use PostgREST under the signed-in caller's RLS policies. Privileged
/// writes call narrow database RPCs that independently verify the stored
/// administrator role. This client never calls an application REST server and
/// never accepts a service-role key.
class ApiService {
  ApiService({
    http.Client? client,
    this.tokenProvider,
    this.forceRefreshTokenProvider,
    SupabaseConfig? config,
    String? supabaseUrl,
    String? supabaseAnonKey,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        config = SupabaseConfig.select(
          config: config,
          url: supabaseUrl,
          anonKey: supabaseAnonKey,
        );

  static const Duration _requestTimeout = Duration(seconds: 25);

  final http.Client _client;
  final bool _ownsClient;

  /// Validated Supabase configuration shared with [AuthService].
  final SupabaseConfig config;

  String get _supabaseUrl => config.url;
  String get _supabaseAnonKey => config.anonKey;

  /// Current Supabase access token, retained only in memory.
  String? token;

  /// Supplies a fresh access token before requests.
  Future<String?> Function()? tokenProvider;

  /// Forced token refresh used once after a 401 response.
  Future<String?> Function()? forceRefreshTokenProvider;

  bool get isConfigured => config.isValid;

  // -------------------------------------------------------------------------
  // Admin-facing endpoint adapters. The returned envelope is retained for the
  // existing typed UI helpers, but all reads/writes are Supabase operations.
  // -------------------------------------------------------------------------

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final segments = _segments(path);
    final params = query ?? const <String, String>{};

    if (segments.length == 2 && segments.first == 'dashboard' && segments[1] == 'stats') {
      final raw = await _rpc('rpc_dashboard_stats', const <String, dynamic>{});
      final stats = _asMap(raw, 'dashboard statistics');
      return _singleEnvelope(<String, dynamic>{
        ...stats,
        'bookingsByStatus': <String, dynamic>{
          'active': stats['activeBookings'] ?? 0,
          'completed': stats['completedBookings'] ?? 0,
          'cancelled': stats['cancelledBookings'] ?? 0,
        },
        'totalWalletBalance': stats['walletBalance'] ?? 0,
      });
    }

    if (segments.length == 2 && segments[0] == 'availability' && segments[1] == 'mine') {
      final page = _positiveInt(params['page'], fallback: 1, maximum: 1000000);
      final limit = _positiveInt(params['limit'], fallback: 50, maximum: kMaxPageSize);
      final raw = await _rpc('rpc_lawyer_my_availability', <String, dynamic>{
        'p_page': page,
        'p_limit': limit,
      });
      return _singleEnvelope(_camelizeMap(_asMap(raw, 'availability page')));
    }

    if (segments.length == 1) {
      final table = segments.single;
      switch (table) {
        case 'users':
          return _listEndpoint('users', params, searchable: const ['name', 'email', 'phone']);
        case 'lawyers':
          return _lawyerPage(params);
        case 'categories':
          return _listEndpoint(
            'legal_categories',
            params,
            searchable: const ['name', 'slug'],
            order: 'name.asc',
          );
        case 'plans':
          return _listEndpoint(
            'plans',
            params,
            searchable: const ['title'],
            order: 'price_value.asc',
          );
        case 'cases':
          return _casePage(params);
        case 'bookings':
          return _withUserIdentity(
              await _listEndpoint('bookings', params, order: 'created_at.desc'));
        case 'subscriptions':
          return _withUserIdentity(
              await _listEndpoint('subscriptions', params, order: 'created_at.desc'));
        case 'notifications':
          return _withUserIdentity(
              await _listEndpoint('notifications', params, order: 'created_at.desc'));
        case 'reviews':
          return _withLawyerNames(
              await _listEndpoint('public_reviews', params, order: 'created_at.desc'));
        case 'chats':
          // Paged like every other admin list (total from Content-Range).
          final page = await _tablePage(
            'chats',
            <String, String>{
              'select': _selectColumns('chats'),
              'order': 'updated_at.desc',
            },
            page: _positiveInt(params['page'], fallback: 1, maximum: 1000000),
            limit: _positiveInt(params['limit'], fallback: kMaxPageSize, maximum: kMaxPageSize),
          );
          return _singleEnvelope(page);
      }
    }

    if (segments.length == 2) {
      final table = segments.first;
      final id = _validateId(segments[1], table);
      switch (table) {
        case 'users':
          return _singleEnvelope(await _one('users', id));
        case 'lawyers':
          return _singleEnvelope(_camelizeMap(_asMap(
            await _rpc('rpc_admin_lawyer_get', <String, dynamic>{'p_lawyer_id': id}),
            'lawyer record',
          )));
        case 'categories':
          return _singleEnvelope(await _one('legal_categories', id));
        case 'plans':
          return _singleEnvelope(await _one('plans', id));
        case 'cases':
          final item = await _one('cases', id);
          final enriched = (await _enrichCases(<Map<String, dynamic>>[item])).single;
          return _singleEnvelope(enriched);
        case 'bookings':
          return _singleEnvelope(await _one('bookings', id));
        case 'subscriptions':
          return _singleEnvelope(await _one('subscriptions', id));
        case 'notifications':
          return _singleEnvelope(await _one('notifications', id));
        case 'reviews':
          return _singleEnvelope(await _one('public_reviews', id));
        case 'chats':
          final chat = await _one('chats', id);
          final messages = await _rows('chat_messages', <String, String>{
            'select': 'id,chat_id,sender_id,sender_name,text,created_at',
            'chat_id': 'eq.$id',
            'order': 'created_at.asc',
            'limit': '$kMaxPageSize',
          });
          return _singleEnvelope(<String, dynamic>{...chat, 'messages': messages});
      }
    }

    throw ApiException('This admin data route is not supported by Supabase.', 404);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final segments = _segments(path);
    if (segments.length != 1 || body is! Map) {
      throw ApiException('Invalid Supabase insert request.', 400);
    }
    final values = Map<String, dynamic>.from(body);
    switch (segments.single) {
      case 'categories':
        final categoryName = values['name']?.toString() ?? '';
        final rawSlug = values['slug']?.toString();
        final generatedSlug = categoryName
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), '');
        // legal_categories.slug is NOT NULL + UNIQUE with no default on the
        // live project, so the insert must always carry a slug. Names without
        // ASCII letters/digits (e.g. Arabic) produce an empty base; a fixed
        // 'category' fallback would collide on the second such category.
        final slug = (rawSlug != null && rawSlug.trim().isNotEmpty)
            ? rawSlug.trim()
            : (generatedSlug.isEmpty ? _fallbackCategorySlug() : generatedSlug);
        return _singleEnvelope(await _insert('legal_categories', <String, dynamic>{
          'name': categoryName,
          'slug': slug,
        }));
      case 'plans':
        return _singleEnvelope(await _insert('plans', _toSnakeMap(values)));
      case 'lawyers':
        return _singleEnvelope(await _saveLawyer(null, values));
      case 'cases':
        final row = await _insert('cases', _toSnakeMap(values));
        final enriched = (await _enrichCases(<Map<String, dynamic>>[row])).single;
        return _singleEnvelope(enriched);
      case 'notifications':
        return _singleEnvelope(await _insert('notifications', _toSnakeMap(values)));
      default:
        throw ApiException('This Supabase insert is not enabled for the admin panel.', 403);
    }
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final segments = _segments(path);
    if (body is! Map) throw ApiException('Invalid Supabase update request.', 400);
    final values = Map<String, dynamic>.from(body);

    if (segments.length == 3 && segments[0] == 'users' && segments[2] == 'role') {
      final id = _validateId(segments[1], 'user');
      final role = values['role']?.toString();
      if (!const {'client', 'lawyer', 'admin'}.contains(role)) {
        throw ApiException('Only client, lawyer, or admin roles can be assigned here.', 400);
      }
      return _singleEnvelope(_camelizeMap(_asMap(await _rpc(
        'rpc_admin_set_user_role',
        <String, dynamic>{'p_user_id': id, 'p_role': role},
      ), 'user role update')));
    }
    if (segments.length == 3 && segments[0] == 'notifications' && segments[2] == 'read') {
      final id = _validateId(segments[1], 'notification');
      if (values['read'] is! bool) throw ApiException('A read state is required.', 400);
      return _singleEnvelope(_camelizeMap(_asMap(await _rpc(
        'rpc_notification_update',
        <String, dynamic>{'p_notification_id': id, 'p_changes': <String, dynamic>{'read': values['read']}},
      ), 'notification read update')));
    }

    if (segments.length != 2) throw ApiException('Invalid Supabase update path.', 400);
    final table = segments.first;
    final id = _validateId(segments[1], table);
    switch (table) {
      case 'users':
        if (values['email'] != null) {
          final existing = await _one('users', id);
          if (values['email'].toString().trim().toLowerCase() !=
              (existing['email']?.toString() ?? '').trim().toLowerCase()) {
            throw ApiException(
              'Sign-in email changes must use Supabase Auth verification.',
              403,
            );
          }
        }
        final profileChanges = <String, dynamic>{
          for (final field in const ['name', 'phone', 'address', 'avatar'])
            if (values.containsKey(field)) field: values[field],
        };
        if (profileChanges.isEmpty) {
          throw ApiException('No editable profile fields were supplied.', 400);
        }
        return _singleEnvelope(await _patch('users', id, _toSnakeMap(profileChanges)));
      case 'lawyers':
        return _singleEnvelope(await _saveLawyer(id, values));
      case 'categories':
        return _singleEnvelope(await _patch('legal_categories', id, _toSnakeMap(values)));
      case 'plans':
        return _singleEnvelope(await _patch('plans', id, _toSnakeMap(values)));
      case 'cases':
        final result = _asMap(await _rpc('rpc_admin_case_update', <String, dynamic>{
          'p_case_id': id,
          'p_changes': _toSnakeMap(values),
        }), 'case update');
        return _singleEnvelope(_camelizeMap(result));
      case 'bookings':
        return _updateBooking(id, values);
      case 'subscriptions':
        final status = values['status']?.toString();
        if (status != 'Cancelled') {
          throw ApiException(
            'Paid subscription activation and expiry require a verified payment-provider workflow.',
            403,
          );
        }
        return _singleEnvelope(_camelizeMap(_asMap(await _rpc(
          'rpc_subscription_cancel',
          <String, dynamic>{'p_subscription_id': id},
        ), 'subscription cancellation')));
      case 'reviews':
        final result = await _rpc('rpc_admin_review_moderate', <String, dynamic>{
          'p_review_id': id,
          'p_rating': values['rating'],
          'p_comment': values['comment'],
        });
        // The RPC returns the full row; reviewer identity stays private.
        final review = _camelizeMap(_asMap(result, 'review moderation'))
          ..remove('userId');
        return _singleEnvelope(review);
      case 'notifications':
        return _singleEnvelope(_camelizeMap(_asMap(await _rpc(
          'rpc_notification_update',
          <String, dynamic>{'p_notification_id': id, 'p_changes': _toSnakeMap(values)},
        ), 'notification update')));
      default:
        throw ApiException('This Supabase update is not enabled for the admin panel.', 403);
    }
  }

  Future<dynamic> delete(String path) async {
    final segments = _segments(path);
    if (segments.length != 2) throw ApiException('Invalid Supabase delete path.', 400);
    final table = segments.first;
    final id = _validateId(segments[1], table);
    switch (table) {
      case 'users':
        throw ApiException(
          'Account deletion is disabled until an approved data-retention workflow exists.',
          403,
        );
      case 'lawyers':
        await _rpc('rpc_admin_lawyer_delete', <String, dynamic>{'p_lawyer_id': id});
        return <String, dynamic>{'success': true, 'data': <String, dynamic>{'id': id}};
      case 'bookings':
        await _rpc('rpc_delete_booking', <String, dynamic>{'p_booking_id': id});
        return <String, dynamic>{'success': true, 'data': <String, dynamic>{'id': id}};
      case 'reviews':
        await _rpc('rpc_admin_review_delete', <String, dynamic>{'p_review_id': id});
        return <String, dynamic>{'success': true, 'data': <String, dynamic>{'id': id}};
      case 'subscriptions':
        await _rpc('rpc_subscription_delete', <String, dynamic>{'p_subscription_id': id});
        return <String, dynamic>{'success': true, 'data': <String, dynamic>{'id': id}};
      case 'categories':
        await _delete('legal_categories', id);
        return <String, dynamic>{'success': true, 'data': <String, dynamic>{'id': id}};
      case 'cases':
        await _delete('cases', id);
        return <String, dynamic>{'success': true, 'data': <String, dynamic>{'id': id}};
      case 'plans':
        await _delete('plans', id);
        return <String, dynamic>{'success': true, 'data': <String, dynamic>{'id': id}};
      case 'notifications':
        await _delete('notifications', id);
        return <String, dynamic>{'success': true, 'data': <String, dynamic>{'id': id}};
      case 'chats':
        await _delete('chats', id);
        return <String, dynamic>{'success': true, 'data': <String, dynamic>{'id': id}};
      default:
        throw ApiException('This Supabase delete is not enabled for the admin panel.', 403);
    }
  }

  // -------------------------------------------------------------------------
  // Endpoint-specific reads and writes
  // -------------------------------------------------------------------------

  static final Random _slugRandom = Random.secure();

  String _fallbackCategorySlug() {
    final suffix = List<String>.generate(
      10,
      (_) => _slugRandom.nextInt(36).toRadixString(36),
    ).join();
    return 'category-$suffix';
  }

  Future<dynamic> _lawyerPage(Map<String, String> query) async {
    final result = await _rpc('rpc_admin_lawyers_page', <String, dynamic>{
      'p_page': _positiveInt(query['page'], fallback: 1, maximum: 1000000),
      'p_limit': _positiveInt(query['limit'], fallback: 50, maximum: kMaxPageSize),
      'p_search': _cleanSearch(query['search']),
      'p_category_id': _emptyToNull(query['categoryId'] ?? query['category_id']),
      'p_is_popular': _optionalBool(query['isPopular'] ?? query['is_popular']),
      'p_is_top': _optionalBool(query['isTop'] ?? query['is_top']),
    });
    return _singleEnvelope(_camelizeMap(_asMap(result, 'lawyer page')));
  }

  Future<dynamic> _casePage(Map<String, String> query) async {
    final filters = <String, String>{
      'select':
          'id,user_id,title,description,client_name,case_type,priority,status,due_date,lawyer_id,category_id,created_at,updated_at',
      'order': 'updated_at.desc',
      if (_emptyToNull(query['status']) != null) 'status': 'eq.${query['status']}',
      if (_emptyToNull(query['priority']) != null) 'priority': 'eq.${query['priority']}',
      if (_emptyToNull(query['userId'] ?? query['user_id']) != null)
        'user_id': 'eq.${query['userId'] ?? query['user_id']}',
      if (_emptyToNull(query['lawyerId'] ?? query['lawyer_id']) != null)
        'lawyer_id': 'eq.${query['lawyerId'] ?? query['lawyer_id']}',
      if (_emptyToNull(query['categoryId'] ?? query['category_id']) != null)
        'category_id': 'eq.${query['categoryId'] ?? query['category_id']}',
    };
    _applySearch(filters, _cleanSearch(query['search']), const [
      'title', 'description', 'client_name', 'case_type',
    ]);
    final page = await _tablePage(
      'cases',
      filters,
      page: _positiveInt(query['page'], fallback: 1, maximum: 1000000),
      limit: _positiveInt(query['limit'], fallback: 50, maximum: kMaxPageSize),
    );
    final enriched = await _enrichCases(_itemsFromPage(page));
    final output = Map<String, dynamic>.from(page)..['items'] = enriched;
    return _singleEnvelope(output);
  }

  Future<dynamic> _listEndpoint(
    String table,
    Map<String, String> query, {
    List<String> searchable = const <String>[],
    String? order,
  }) async {
    final filters = <String, String>{
      'select': _selectColumns(table),
      'order': ?order,
    };
    final status = _emptyToNull(query['status']);
    if (status != null && table == 'bookings') {
      filters['status'] = 'eq.${status == 'Active' ? 'Confirmed' : status}';
    } else if (status != null && table == 'subscriptions') {
      filters['status'] = 'eq.$status';
    }
    final userId = _emptyToNull(query['userId'] ?? query['user_id']);
    if (userId != null && table == 'notifications') filters['user_id'] = 'eq.$userId';
    final role = _emptyToNull(query['role']);
    if (role != null && table == 'users') filters['role'] = 'eq.$role';
    final lawyerId = _emptyToNull(query['lawyerId'] ?? query['lawyer_id']);
    if (lawyerId != null && table == 'public_reviews') filters['lawyer_id'] = 'eq.$lawyerId';
    _applySearch(filters, _cleanSearch(query['search']), searchable);

    final page = await _tablePage(
      table,
      filters,
      page: _positiveInt(query['page'], fallback: 1, maximum: 1000000),
      limit: _positiveInt(query['limit'], fallback: 50, maximum: kMaxPageSize),
    );
    return _singleEnvelope(page);
  }

  Future<Map<String, dynamic>> _updateBooking(String id, Map<String, dynamic> values) async {
    final scheduleFields = const ['lawyerId', 'lawyer_id', 'date', 'time', 'hours'];
    final scheduleChanged = scheduleFields.any(values.containsKey);
    if (scheduleChanged) {
      if (values.containsKey('status')) {
        throw ApiException('Update booking status and reschedule separately.', 400);
      }
      final existing = await _one('bookings', id);
      final result = await _rpc('rpc_admin_reschedule_booking', <String, dynamic>{
        'p_booking_id': id,
        'p_lawyer_id': values['lawyerId'] ?? values['lawyer_id'] ?? existing['lawyerId'],
        'p_date': values['date'] ?? existing['date'],
        'p_time': values['time'] ?? existing['time'],
        'p_hours': values['hours'] ?? existing['hours'],
      });
      final row = _asMap(result, 'booking reschedule');
      if (row['error'] != null) throw _domainError(row['error'].toString());
      return _singleEnvelope(_camelizeMap(row));
    }
    final status = values['status']?.toString();
    if (status == null || status.isEmpty) {
      throw ApiException('A booking status is required.', 400);
    }
    final normalized = status == 'Active' ? 'Confirmed' : status;
    final result = await _rpc('rpc_admin_set_booking_status', <String, dynamic>{
      'p_booking_id': id,
      'p_status': normalized,
    });
    return _singleEnvelope(_camelizeMap(_asMap(result, 'booking status update')));
  }

  Future<Map<String, dynamic>> _saveLawyer(String? id, Map<String, dynamic> values) async {
    final result = await _rpc('rpc_admin_lawyer_save', <String, dynamic>{
      'p_lawyer_id': id,
      'p_name': values['name'],
      'p_user_id': values.containsKey('userId') ? values['userId'] : null,
      'p_category_id': values['categoryId'] ?? values['category_id'],
      'p_experience': values['experience'],
      'p_price': values['price'],
      'p_price_value': values['priceValue'] ?? values['price_value'],
      'p_image': values['image'],
      'p_rating': values['rating'],
      'p_location': values['location'],
      'p_bio': values['bio'],
      'p_is_popular': values['isPopular'] ?? values['is_popular'],
      'p_is_top': values['isTop'] ?? values['is_top'],
    });
    return _camelizeMap(_asMap(result, 'lawyer save'));
  }

  static final RegExp _lookupId = RegExp(r'^[A-Za-z0-9_-]{1,200}$');

  /// Best-effort `id -> row` lookup of display columns for [ids].
  ///
  /// Only safe ids are sent in the `in.(...)` filter. A failed lookup (for
  /// example a lawyer session that may read only its own profile) leaves the
  /// rows unresolved instead of failing the whole list.
  Future<Map<String, Map<String, dynamic>>> _lookupById(
    String table,
    String select,
    Iterable<String> ids,
  ) async {
    final clean = ids.where(_lookupId.hasMatch).toSet();
    if (clean.isEmpty) return const <String, Map<String, dynamic>>{};
    try {
      final rows = await _rows(table, <String, String>{
        'select': select,
        'id': 'in.(${clean.join(',')})',
      });
      return <String, Map<String, dynamic>>{
        for (final row in rows) row['id'].toString(): row,
      };
    } on ApiException {
      return const <String, Map<String, dynamic>>{};
    }
  }

  /// Adds `userName`/`userEmail` from `users(id,name,email)` to each item.
  Future<dynamic> _withUserIdentity(dynamic envelope) async {
    final page = listPageOf(envelope);
    final items = _itemsFromPage(page);
    final users = await _lookupById(
      'users',
      'id,name,email',
      items.map((row) => row['userId']?.toString() ?? ''),
    );
    return _singleEnvelope(<String, dynamic>{
      ...page,
      'items': items.map((row) {
        final user = users[row['userId']?.toString()];
        return <String, dynamic>{
          ...row,
          'userName': user?['name']?.toString() ?? '',
          'userEmail': user?['email']?.toString() ?? '',
        };
      }).toList(growable: false),
    });
  }

  /// Adds `lawyerName` from the public `lawyers(id,name)` columns.
  Future<dynamic> _withLawyerNames(dynamic envelope) async {
    final page = listPageOf(envelope);
    final items = _itemsFromPage(page);
    final lawyers = await _lookupById(
      'lawyers',
      'id,name',
      items.map((row) => row['lawyerId']?.toString() ?? ''),
    );
    return _singleEnvelope(<String, dynamic>{
      ...page,
      'items': items.map((row) => <String, dynamic>{
            ...row,
            'lawyerName': lawyers[row['lawyerId']?.toString()]?['name']?.toString() ?? '',
          }).toList(growable: false),
    });
  }

  Future<List<Map<String, dynamic>>> _enrichCases(List<Map<String, dynamic>> cases) async {
    if (cases.isEmpty) return cases;
    final categoryIds = cases
        .map((row) => row['categoryId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final lawyerIds = cases
        .map((row) => row['lawyerId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final categoriesFuture = categoryIds.isEmpty
        ? Future.value(const <Map<String, dynamic>>[])
        : _rows('legal_categories', <String, String>{
            'select': 'id,name',
            'id': 'in.(${categoryIds.join(',')})',
          });
    final lawyersFuture = lawyerIds.isEmpty
        ? Future.value(const <Map<String, dynamic>>[])
        : _rows('lawyers', <String, String>{
            'select': 'id,name',
            'id': 'in.(${lawyerIds.join(',')})',
          });
    final values = await Future.wait([categoriesFuture, lawyersFuture]);
    final categoryNames = <String, String>{
      for (final row in values[0]) row['id'].toString(): row['name'].toString(),
    };
    final lawyerNames = <String, String>{
      for (final row in values[1]) row['id'].toString(): row['name'].toString(),
    };
    return cases.map((row) => <String, dynamic>{
      ...row,
      'categoryName': categoryNames[row['categoryId']] ?? row['caseType'] ?? '',
      'lawyerName': lawyerNames[row['lawyerId']] ?? '',
    }).toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // PostgREST and Authenticated RPC transport
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> _tablePage(
    String table,
    Map<String, String> filters, {
    required int page,
    required int limit,
  }) async {
    final query = <String, String>{
      ...filters,
      'limit': '$limit',
      'offset': '${(page - 1) * limit}',
    };
    final response = await _send(
      'GET',
      _restUri(table, query),
      extraHeaders: const <String, String>{'Prefer': 'count=exact'},
    );
    final data = _decode(response);
    if (data is! List) throw ApiException('Supabase returned an invalid $table page.', 502);
    final rows = _asRows(data, table);
    final exactTotal = _contentRangeTotal(response);
    final total = exactTotal ?? (page - 1) * limit + rows.length;
    final totalPages = total == 0 ? 1 : (total + limit - 1) ~/ limit;
    return <String, dynamic>{
      'items': rows,
      'page': page,
      'limit': limit,
      'total': total,
      'totalPages': totalPages,
      // Without an exact count a full page may have more rows behind it.
      'hasMore': page < totalPages || (exactTotal == null && rows.length >= limit),
    };
  }

  Future<List<Map<String, dynamic>>> _rows(
    String table,
    Map<String, String> query,
  ) async {
    final response = await _send('GET', _restUri(table, query));
    final data = _decode(response);
    return _asRows(data, table);
  }

  Future<Map<String, dynamic>> _one(String table, String id) async {
    final rows = await _rows(table, <String, String>{
      // bookings is readable only column-by-column (idempotency_key_hash is
      // never granted), so `*` would be denied once the grants are applied.
      'select': table == 'bookings' ? _selectColumns(table) : '*',
      'id': 'eq.$id',
      'limit': '2',
    });
    if (rows.isEmpty) throw ApiException('Record not found.', 404);
    if (rows.length > 1) throw ApiException('Supabase returned an ambiguous record.', 502);
    return rows.single;
  }

  Future<Map<String, dynamic>> _insert(String table, Map<String, dynamic> body) async {
    final response = await _send(
      'POST',
      _restUri(table, const <String, String>{'select': '*'}),
      body: _toSnakeMap(body),
      extraHeaders: const <String, String>{'Prefer': 'return=representation'},
    );
    return _oneResult(_decode(response), 'insert');
  }

  Future<Map<String, dynamic>> _patch(
    String table,
    String id,
    Map<String, dynamic> body,
  ) async {
    final response = await _send(
      'PATCH',
      _restUri(table, <String, String>{'id': 'eq.$id', 'select': '*'}),
      body: _toSnakeMap(body),
      extraHeaders: const <String, String>{'Prefer': 'return=representation'},
    );
    return _oneResult(_decode(response), 'update');
  }

  Future<void> _delete(String table, String id) async {
    final response = await _send(
      'DELETE',
      _restUri(table, <String, String>{'id': 'eq.$id'}),
      extraHeaders: const <String, String>{'Prefer': 'return=representation'},
    );
    final data = _decode(response);
    if (data is! List || data.isEmpty) throw ApiException('Record not found.', 404);
  }

  Future<dynamic> _rpc(String functionName, Map<String, dynamic> args) async {
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(functionName)) {
      throw ApiException('Invalid Supabase RPC name.', 400);
    }
    final response = await _send(
      'POST',
      _restUri('rpc/$functionName', const <String, String>{}),
      body: args,
    );
    return _decode(response);
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    if (!isConfigured) {
      throw ApiException(config.errorMessage, 503);
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final effectiveToken = await _freshToken(force: attempt == 1);
      if (effectiveToken == null || effectiveToken.isEmpty) {
        throw ApiException('Your Supabase session has expired. Please sign in again.', 401);
      }
      final headers = <String, String>{
        'apikey': _supabaseAnonKey,
        'Authorization': 'Bearer $effectiveToken',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
        ...extraHeaders,
      };
      final response = await _request(method, uri, headers: headers, body: body);
      if (response.statusCode == 401 && attempt == 0) continue;
      return response;
    }
    throw ApiException('Your Supabase session has expired. Please sign in again.', 401);
  }

  Future<http.Response> _request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    Object? body,
  }) async {
    try {
      final encoded = body == null ? null : jsonEncode(body);
      switch (method) {
        case 'GET':
          return await _client.get(uri, headers: headers).timeout(_requestTimeout);
        case 'POST':
          return await _client.post(uri, headers: headers, body: encoded).timeout(_requestTimeout);
        case 'PATCH':
          return await _client.patch(uri, headers: headers, body: encoded).timeout(_requestTimeout);
        case 'DELETE':
          return await _client.delete(uri, headers: headers, body: encoded).timeout(_requestTimeout);
        default:
          throw ApiException('Unsupported Supabase request method.', 405);
      }
    } on TimeoutException {
      throw ApiException('Supabase request timed out. Please try again.', 0);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Could not reach Supabase. Check your connection and try again.', 0);
    }
  }

  Future<String?> _freshToken({required bool force}) async {
    final provider = force ? forceRefreshTokenProvider ?? tokenProvider : tokenProvider;
    if (provider != null) {
      try {
        final fresh = await provider();
        if (fresh != null && fresh.isNotEmpty) token = fresh;
      } catch (_) {
        // Retain the last token only for a transient refresh failure; Supabase
        // still makes the final authorization decision.
      }
    }
    return token;
  }

  Uri _restUri(String path, Map<String, String> query) {
    final base = _supabaseUrl.endsWith('/')
        ? _supabaseUrl.substring(0, _supabaseUrl.length - 1)
        : _supabaseUrl;
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    if (cleanPath.isEmpty || cleanPath.contains('..')) {
      throw ApiException('Invalid Supabase resource path.', 400);
    }
    return Uri.parse('$base/rest/v1/$cleanPath').replace(
      queryParameters: query.isEmpty ? null : query,
    );
  }

  dynamic _decode(http.Response response) {
    dynamic body;
    try {
      body = response.body.trim().isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw ApiException('Supabase returned an unexpected response.', 502);
      }
      body = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    final message = body is Map
        ? (body['message'] ?? body['msg'] ?? body['error_description'] ?? body['error'])?.toString()
        : null;
    String? field(String key) {
      final value = body is Map ? body[key] : null;
      return value?.toString();
    }
    throw ApiException(
      message?.isNotEmpty == true ? message! : 'Supabase request failed (${response.statusCode}).',
      response.statusCode,
      code: field('code'),
      details: field('details'),
      hint: field('hint'),
    );
  }

  List<Map<String, dynamic>> _asRows(dynamic data, String label) {
    if (data is! List) throw ApiException('Supabase returned an invalid $label list.', 502);
    return data.map((row) {
      if (row is! Map) throw ApiException('Supabase returned an invalid $label record.', 502);
      return _camelizeMap(row);
    }).toList(growable: false);
  }

  Map<String, dynamic> _oneResult(dynamic data, String operation) {
    if (data is List) {
      if (data.isEmpty) throw ApiException('Supabase returned no row for $operation.', 404);
      if (data.length > 1 || data.first is! Map) {
        throw ApiException('Supabase returned an invalid $operation result.', 502);
      }
      return _camelizeMap(data.first as Map);
    }
    if (data is Map) return _camelizeMap(data);
    throw ApiException('Supabase returned an invalid $operation result.', 502);
  }

  Map<String, dynamic> _asMap(dynamic value, String label) {
    if (value is! Map) throw ApiException('Supabase returned an invalid $label.', 502);
    return Map<String, dynamic>.from(value);
  }

  List<Map<String, dynamic>> _itemsFromPage(Map<String, dynamic> page) {
    final items = page['items'];
    if (items is! List) throw ApiException('Supabase returned an invalid page.', 502);
    return items.whereType<Map>().map(_camelizeMap).toList(growable: false);
  }

  String _selectColumns(String table) {
    switch (table) {
      case 'users':
        return 'id,name,email,phone,role,avatar,address,created_at,updated_at';
      case 'bookings':
        return 'id,user_id,lawyer_id,lawyer_name,date,time,hours,total_price,status,created_at,updated_at';
      case 'subscriptions':
        return 'id,user_id,plan_id,plan_title,status,start_date,end_date,created_at,updated_at';
      case 'notifications':
        return 'id,user_id,title,content,type,icon,read,created_at,updated_at';
      case 'public_reviews':
        return 'id,user_name,lawyer_id,rating,comment,created_at,updated_at';
      case 'plans':
        return 'id,title,price,price_value,color,features,is_popular,created_at,updated_at';
      case 'legal_categories':
        return 'id,name,slug,created_at,updated_at';
      case 'chats':
        return 'id,participants,participant_names,last_message,created_at,updated_at';
      default:
        return '*';
    }
  }

  void _applySearch(Map<String, String> filters, String? value, List<String> fields) {
    if (value == null || fields.isEmpty) return;
    final safe = value
        .replaceAll(RegExp(r'[,()"*%_\\]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (safe.isEmpty) return;
    filters['or'] = '(${fields.map((field) => '$field.ilike.*$safe*').join(',')})';
  }

  String? _cleanSearch(String? raw) {
    final value = raw?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? _emptyToNull(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  bool? _optionalBool(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final clean = value.trim().toLowerCase();
    if (clean == 'true') return true;
    if (clean == 'false') return false;
    throw ApiException('Invalid boolean filter.', 400);
  }

  int _positiveInt(String? value, {required int fallback, required int maximum}) {
    if (value == null || value.trim().isEmpty) return fallback;
    final result = int.tryParse(value);
    if (result == null || result < 1 || result > maximum) {
      throw ApiException('Invalid pagination request.', 400);
    }
    return result;
  }

  int? _contentRangeTotal(http.Response response) {
    final range = response.headers['content-range'];
    final match = range == null ? null : RegExp(r'/([0-9]+|\*)\s*$').firstMatch(range);
    final value = match?.group(1);
    return value == null || value == '*' ? null : int.tryParse(value);
  }

  List<String> _segments(String path) {
    final clean = path.trim().replaceFirst(RegExp(r'^/+'), '').replaceFirst(RegExp(r'/+$'), '');
    if (clean.isEmpty || clean.split('/').any((segment) => segment.isEmpty || segment == '..')) {
      throw ApiException('Invalid Supabase resource path.', 400);
    }
    return clean.split('/');
  }

  String _validateId(String value, String label) {
    final id = value.trim();
    if (id.isEmpty || id.length > 200 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw ApiException('Invalid $label ID.', 400);
    }
    return id;
  }

  Map<String, dynamic> _toSnakeMap(Map<String, dynamic> value) => <String, dynamic>{
        for (final entry in value.entries) _snakeKey(entry.key): entry.value,
      };

  String _snakeKey(String value) => value.replaceAllMapped(
        RegExp(r'[A-Z]'),
        (match) => '_${match.group(0)!.toLowerCase()}',
      );

  ApiException _domainError(String code) {
    // The domain code is kept on `code`, so api_errors.dart can map it.
    switch (code) {
      case 'SLOT_TAKEN':
      case 'BOOKING_OVERLAP':
        return ApiException('That appointment time is no longer available.', 409, code: code);
      case 'NO_AVAILABILITY':
      case 'TIME_NOT_AVAILABLE':
        return ApiException('The lawyer is not available at the selected time.', 409, code: code);
      case 'BOOKING_STATUS_IS_TERMINAL':
      case 'TERMINAL_BOOKING_CANNOT_BE_RESCHEDULED':
        return ApiException('This booking can no longer be changed.', 409, code: code);
      case 'LAWYER_ACCOUNT_ALREADY_LINKED':
        return ApiException('That lawyer account is already linked to another profile.', 409, code: code);
      case 'CATEGORY_REQUIRED':
      case 'CATEGORY_NOT_FOUND':
      case 'LAWYER_ACCOUNT_REQUIRED':
      case 'INVALID_LAWYER_PROFILE':
        return ApiException('Check the lawyer name, category, account, and hourly rate.', 400, code: code);
      default:
        return ApiException('Supabase could not complete the request ($code).', 400, code: code);
    }
  }

  dynamic _singleEnvelope(Map<String, dynamic> data) => <String, dynamic>{
        'success': true,
        'data': data,
      };


  void dispose() {
    if (_ownsClient) _client.close();
  }
}

/// Thrown for Supabase responses and transport failures.
class ApiException implements Exception {
  final String message;
  final int statusCode;

  /// PostgREST / PostgreSQL error code (for example `PGRST202`, `PGRST205`,
  /// `23502`), retained so failed requests can be diagnosed precisely.
  final String? code;

  /// PostgREST `details` and `hint` fields, when the server supplied them.
  final String? details;
  final String? hint;

  ApiException(this.message, this.statusCode, {this.code, this.details, this.hint});

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => message;
}

/// The server caps list pages at 100 records.
const int kMaxPageSize = 100;

Map<String, dynamic> listPageOf(dynamic res) {
  final data = res is Map ? res['data'] : null;
  if (data is! Map) throw ApiException('Unexpected Supabase page response.', 502);
  return Map<String, dynamic>.from(data);
}

List<Map<String, dynamic>> itemsOf(dynamic res) {
  final items = listPageOf(res)['items'];
  if (items is! List) throw ApiException('Unexpected Supabase page response.', 502);
  return items.whereType<Map>().map(_camelizeMap).toList(growable: false);
}

List<dynamic> listDataOf(dynamic res) {
  final data = res is Map ? res['data'] : null;
  if (data is! List) throw ApiException('Unexpected Supabase list response.', 502);
  return data;
}

Map<String, dynamic> objectDataOf(dynamic res) {
  final data = res is Map ? res['data'] : null;
  if (data is! Map) throw ApiException('Unexpected Supabase object response.', 502);
  return Map<String, dynamic>.from(data);
}

String _camelKey(String value) => value.replaceAllMapped(
      RegExp(r'_([a-z])'),
      (match) => match.group(1)!.toUpperCase(),
    );

Map<String, dynamic> _camelizeMap(Map value) => <String, dynamic>{
      for (final entry in value.entries)
        if (entry.key is String) _camelKey(entry.key as String): _camelize(entry.value),
    };

dynamic _camelize(dynamic value) {
  if (value is Map) return _camelizeMap(value);
  if (value is List) return value.map(_camelize).toList(growable: false);
  return value;
}
