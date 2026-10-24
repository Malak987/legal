import '../config/ai_config.dart';
import '../models/lawyer_availability.dart';
import '../models/legal_category.dart';
import '../models/paginated_result.dart';
import '../models/product_model.dart';
import 'api_client.dart';

/// Repository for application data during the Express-to-Supabase migration.
///
/// The lawyer list/detail reads use public PostgREST only when Supabase and an
/// applicable explicit build flag are configured. The favorites slice uses
/// authenticated PostgREST/RPC under RLS when its own flag is enabled. Other
/// resource operations remain on the legacy API until reviewed individually.
class AppRepository {
  AppRepository(this._api);
  final ApiClient _api;

  /// The signed-in user's ID, or `null` when signed out.
  String? get currentUid => _api.currentUid;

  String _requireUid() {
    final uid = _api.currentUid;
    if (uid == null || uid.isEmpty) {
      throw ApiException('You are not signed in.', 401);
    }
    return uid;
  }

  // ---------------- Lawyers ----------------

  static const int lawyerPageSize = 20;
  static const int _maxLawyerPageSize = 100;
  static const String _publicLawyerColumns =
      'id,category_id,name,specialty,price,price_value,image,rating,location,experience,bio,is_popular,is_top';

  /// Fetches one page of lawyers, optionally filtered to popular or top-rated
  /// results. The Supabase and Express adapters expose the same page contract.
  Future<PaginatedResult<Product>> fetchLawyerPage({
    String search = '',
    String? categoryId,
    bool? isPopular,
    bool? isTop,
    int page = 1,
    int limit = lawyerPageSize,
  }) async {
    if (page < 1 || limit < 1 || limit > _maxLawyerPageSize) {
      throw ApiException('Invalid lawyer page request.', 400);
    }
    final safeCategoryId = _validatedCategoryId(categoryId);

    if (_api.usesSupabaseLawyerCatalog) {
      final safeSearch = _postgrestSearchTerm(search);
      final result = await _api.getSupabasePublicLawyerPage(
        query: {
          'select': _publicLawyerColumns,
          'order': 'rating.desc',
          if (safeCategoryId != null) 'category_id': 'eq.$safeCategoryId',
          if (safeSearch.isNotEmpty)
            'or': '(name.ilike.*$safeSearch*,specialty.ilike.*$safeSearch*,location.ilike.*$safeSearch*)',
          if (isPopular != null) 'is_popular': 'eq.$isPopular',
          if (isTop != null) 'is_top': 'eq.$isTop',
        },
        page: page,
        limit: limit,
      );
      final items = result.items.map(_toProduct).toList(growable: false);
      return PaginatedResult<Product>(
        items: items,
        page: result.page,
        limit: result.limit,
        total: result.total,
        totalPages: result.totalPages,
        hasMore: result.hasMore,
      );
    }

    // Explicit legacy-mode fallback. The migration ledger does not count this
    // as a production cutover until the hosted Supabase path is authorized and
    // verified and all consumers of these routes have moved.
    final data = await _api.get('lawyers', query: {
      'page': '$page',
      'limit': '$limit',
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (safeCategoryId != null) 'categoryId': safeCategoryId,
      if (isPopular != null) 'isPopular': '$isPopular',
      if (isTop != null) 'isTop': '$isTop',
    });
    return _parseLegacyLawyerPage(data, requestedPage: page, requestedLimit: limit);
  }

  /// Compatibility helper for screens that only need an initial list. New
  /// catalogue views should use [fetchLawyerPage] and expose `hasMore`.
  Future<List<Product>> fetchLawyers({
    String search = '',
    String? categoryId,
    bool? isPopular,
    bool? isTop,
  }) async {
    final page = await fetchLawyerPage(
      search: search,
      categoryId: categoryId,
      isPopular: isPopular,
      isTop: isTop,
      page: 1,
      limit: _maxLawyerPageSize,
    );
    return page.items;
  }

  PaginatedResult<Product> _parseLegacyLawyerPage(
    dynamic data, {
    required int requestedPage,
    required int requestedLimit,
  }) {
    if (data is! Map) {
      throw ApiException.invalidResponse('The lawyer list response was invalid.');
    }
    final rawItems = data['items'];
    if (rawItems is! List) {
      throw ApiException.invalidResponse('The lawyer list response was invalid.');
    }
    final items = <Product>[];
    for (final row in rawItems) {
      if (row is! Map) {
        throw ApiException.invalidResponse('The lawyer list contained an invalid record.');
      }
      try {
        items.add(_toProduct(Map<String, dynamic>.from(row)));
      } on TypeError {
        throw ApiException.invalidResponse('The lawyer list contained an invalid record.');
      }
    }
    if (items.length > requestedLimit) {
      throw ApiException.invalidResponse('The lawyer list exceeded the requested page size.');
    }

    final responsePage = _readPageInteger(
      data['page'],
      field: 'page',
      fallback: requestedPage,
      minimum: 1,
    );
    final responseLimit = _readPageInteger(
      data['limit'],
      field: 'limit',
      fallback: requestedLimit,
      minimum: 1,
    );
    if (responsePage != requestedPage || responseLimit != requestedLimit) {
      throw ApiException.invalidResponse('The lawyer list page metadata did not match the request.');
    }

    final offset = (requestedPage - 1) * requestedLimit;
    final parsedTotal = _readOptionalPageInteger(data['total'], field: 'total');
    final total = parsedTotal ?? offset + items.length;
    final parsedTotalPages =
        _readOptionalPageInteger(data['totalPages'], field: 'totalPages');
    final totalPages = parsedTotalPages ??
        (parsedTotal == null
            ? requestedPage + (items.length == requestedLimit ? 1 : 0)
            : ((total + requestedLimit - 1) ~/ requestedLimit));
    if (totalPages < 1 || items.length > total) {
      throw ApiException.invalidResponse('The lawyer list totals were invalid.');
    }

    return PaginatedResult<Product>(
      items: items,
      page: requestedPage,
      limit: requestedLimit,
      total: total,
      totalPages: totalPages,
      hasMore: parsedTotal == null && parsedTotalPages == null
          ? items.length == requestedLimit
          : requestedPage < totalPages,
    );
  }

  int _readPageInteger(
    dynamic value, {
    required String field,
    required int fallback,
    required int minimum,
  }) {
    final parsed = _readOptionalPageInteger(value, field: field) ?? fallback;
    if (parsed < minimum) {
      throw ApiException.invalidResponse('The lawyer list $field was invalid.');
    }
    return parsed;
  }

  int? _readOptionalPageInteger(dynamic value, {required String field}) {
    if (value == null) return null;
    int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num && value.isFinite && value == value.roundToDouble()) {
      parsed = value.toInt();
    } else if (value is String) {
      parsed = int.tryParse(value);
    }
    if (parsed == null || parsed < 0) {
      throw ApiException.invalidResponse('The lawyer list $field was invalid.');
    }
    return parsed;
  }

  /// Fetches a single lawyer, or `null` when the record is gone.
  Future<Product?> fetchLawyer(String id) async {
    if (id.isEmpty) return null;
    if (_api.usesSupabaseLawyerCatalog || _api.usesSupabaseFavorites) {
      // Favorite entries need their public lawyer row even when only the
      // favorites migration flag is enabled. The public select still excludes
      // the private lawyer owner ID.
      // Lawyer IDs are generated as UUID/Firebase-style opaque identifiers.
      // Keep PostgREST's filter grammar out of a caller-supplied filter value.
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
        throw ApiException('Invalid lawyer ID.', 400);
      }
      final rows = await _api.getSupabasePublicLawyers(query: {
        'select': _publicLawyerColumns,
        'id': 'eq.$id',
        'limit': '1',
      });
      return rows.isEmpty ? null : _toProduct(rows.first);
    }

    try {
      final data = await _api.get('lawyers/$id');
      if (data is! Map) {
        throw ApiException.invalidResponse('The lawyer detail response was invalid.');
      }
      try {
        return _toProduct(Map<String, dynamic>.from(data));
      } on TypeError {
        throw ApiException.invalidResponse('The lawyer detail response was invalid.');
      }
    } on ApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  /// Removes PostgREST's filter delimiters and wildcard characters from a
  /// user-entered search string before embedding it in a server-side `or`.
  /// Unicode text (including Arabic names) and ordinary punctuation such as
  /// spaces and hyphens remain searchable.
  String _postgrestSearchTerm(String value) {
    var safe = value.trim();
    for (final character in <String>[
      ',',
      '(',
      ')',
      '"',
      "'",
      String.fromCharCode(92),
      '*',
      '%',
      '_',
    ]) {
      safe = safe.replaceAll(character, ' ');
    }
    return safe.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _validatedCategoryId(String? value) {
    final id = value?.trim();
    if (id == null || id.isEmpty) return null;
    if (id.length > 160 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw ApiException('Invalid legal category ID.', 400);
    }
    return id;
  }

  /// Reads the public legal taxonomy through the same REST API used by the
  /// admin category manager. No static category list is treated as data.
  Future<List<LegalCategory>> fetchCategories({String search = ''}) async {
    final data = await _api.get('categories', query: {
      'page': '1',
      'limit': '100',
      if (search.trim().isNotEmpty) 'search': search.trim(),
    });
    if (data is! Map || data['items'] is! List) {
      throw ApiException.invalidResponse('The category list response was invalid.');
    }
    final categories = <LegalCategory>[];
    for (final row in data['items'] as List) {
      if (row is! Map) {
        throw ApiException.invalidResponse('The category list contained an invalid record.');
      }
      final category = LegalCategory.fromJson(Map<String, dynamic>.from(row));
      if (category.id.trim().isEmpty || category.name.trim().isEmpty) {
        throw ApiException.invalidResponse('The category list contained an invalid record.');
      }
      categories.add(category);
    }
    return categories;
  }

  /// The availability a lawyer has published.
  Future<List<LawyerAvailability>> fetchAvailability(String lawyerId) async {
    if (lawyerId.isEmpty) return const <LawyerAvailability>[];
    final data = await _api.get('availability', query: {
      'lawyerId': lawyerId,
      'limit': '100',
    });
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(LawyerAvailability.fromJson).toList();
  }

  Product _toProduct(Map<String, dynamic> json) {
    final id = _optionalString(json['id'], 'id');
    final name = _optionalString(json['name'], 'name');
    if (id == null || id.trim().isEmpty || name == null) {
      throw ApiException.invalidResponse('The lawyer response omitted a required ID or name.');
    }

    final priceValue = _firstField(json, 'priceValue', 'price_value');
    final categoryId = _firstField(json, 'categoryId', 'category_id');
    final isPopular = _firstField(json, 'isPopular', 'is_popular');
    final isTop = _firstField(json, 'isTop', 'is_top');
    final userId = _firstField(json, 'userId', 'user_id');
    final image = _firstField(json, 'image', 'imagePath');

    return Product(
      id: id,
      imagePath: _optionalString(image, 'image') ?? '',
      name: name,
      price: _optionalString(json['price'], 'price') ?? '',
      specialty: _optionalString(json['specialty'], 'specialty'),
      categoryId: _optionalString(categoryId, 'category_id'),
      rating: _optionalNumber(json['rating'], 'rating'),
      location: _optionalString(json['location'], 'location'),
      priceValue: _optionalNumber(priceValue, 'price_value'),
      experience: _optionalString(json['experience'], 'experience'),
      bio: _optionalString(json['bio'], 'bio'),
      userId: _optionalString(userId, 'user_id'),
      isPopular: _optionalBool(isPopular, 'is_popular'),
      isTop: _optionalBool(isTop, 'is_top'),
    );
  }

  dynamic _firstField(Map<String, dynamic> json, String primary, String legacy) =>
      json[primary] ?? json[legacy];

  String? _optionalString(dynamic value, String field) {
    if (value == null) return null;
    if (value is String) return value;
    throw ApiException.invalidResponse('The lawyer response contained an invalid $field.');
  }

  double? _optionalNumber(dynamic value, String field) {
    if (value == null) return null;
    if (value is num && value.isFinite) return value.toDouble();
    throw ApiException.invalidResponse('The lawyer response contained an invalid $field.');
  }

  bool? _optionalBool(dynamic value, String field) {
    if (value == null) return null;
    if (value is bool) return value;
    throw ApiException.invalidResponse('The lawyer response contained an invalid $field.');
  }

  // ---------------- Cases ----------------

  Future<List<Map<String, dynamic>>> fetchMyCases() async {
    final data = await _api.get('cases', query: {'limit': '100'});
    return (data['items'] as List).cast<Map<String, dynamic>>();
  }

  /// Fetches one caller-authorized case by its stable API ID.
  Future<Map<String, dynamic>> fetchCase(String caseId) async {
    final id = caseId.trim();
    if (id.isEmpty) throw ApiException('A case ID is required.', 400);
    final data = await _api.get('cases/${Uri.encodeComponent(id)}');
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw ApiException.invalidResponse('The case detail response was invalid.');
  }

  Future<Map<String, dynamic>> createCase({
    required String title,
    String? categoryId,
    String? lawyerId,
    String description = '',
    String clientName = '',
    String caseType = '',
    String priority = 'Medium',
    String dueDate = '',
  }) async {
    return await _api.post('cases', body: {
      'title': title,
      'description': description,
      'clientName': clientName,
      'caseType': caseType,
      if (categoryId != null && categoryId.trim().isNotEmpty)
        'categoryId': _validatedCategoryId(categoryId),
      if (lawyerId != null && lawyerId.trim().isNotEmpty) 'lawyerId': lawyerId.trim(),
      'priority': priority,
      'dueDate': dueDate,
    }) as Map<String, dynamic>;
  }

  // ---------------- Bookings ----------------

  Future<List<Map<String, dynamic>>> fetchBookings({String? status}) async {
    final data = await _api.get('bookings', query: {
      'limit': '100',
      if (status != null && status.isNotEmpty) 'status': status,
    });
    return (data['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createBooking({
    required String lawyerId,
    required String lawyerName,
    required String date,
    required String time,
    required int hours,
    double totalPrice = 0,
  }) async {
    return await _api.post('bookings', body: {
      'lawyerId': lawyerId,
      'lawyerName': lawyerName,
      'date': date,
      'time': time,
      'hours': hours,
      'totalPrice': totalPrice,
    }) as Map<String, dynamic>;
  }

  Future<void> updateBookingStatus(String bookingId, String status) async {
    await _api.put('bookings/$bookingId', body: {'status': status});
  }

  // ---------------- Tasks ----------------

  Future<List<Map<String, dynamic>>> fetchTasks() async {
    final data = await _api.get('tasks', query: {'limit': '100'});
    return (data['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createTask({
    required String title,
    String description = '',
    String dueDate = '',
    String priority = 'Medium',
    String status = 'Pending',
  }) async {
    return await _api.post('tasks', body: {
      'title': title,
      'description': description,
      'dueDate': dueDate,
      'priority': priority,
      'status': status,
    }) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateTask(
    String taskId,
    Map<String, dynamic> updates,
  ) async {
    return await _api.put('tasks/$taskId', body: updates)
        as Map<String, dynamic>;
  }

  Future<void> deleteTask(String taskId) async {
    await _api.delete('tasks/$taskId');
  }

  // ---------------- Plans & Subscriptions ----------------

  Future<List<Map<String, dynamic>>> fetchPlans() async {
    final data = await _api.get('plans', query: {'limit': '100'});
    return (data['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchMySubscriptions() async {
    final data = await _api.get('subscriptions', query: {'limit': '100'});
    return (data['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createSubscription({
    required String planId,
  }) async {
    return await _api.post('subscriptions', body: {
      'planId': planId,
    }) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> cancelSubscription(String subscriptionId) async {
    return await _api.put('subscriptions/$subscriptionId', body: {
      'status': 'Cancelled',
    }) as Map<String, dynamic>;
  }

  // ---------------- Notifications ----------------

  Future<List<Map<String, dynamic>>> fetchNotifications(String userId) async {
    final data =
        await _api.get('notifications/$userId', query: {'limit': '100'});
    return (data['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchMyNotifications() async {
    return fetchNotifications(_requireUid());
  }

  Future<void> markNotificationRead(String notificationId, bool read) async {
    await _api.put('notifications/$notificationId/read', body: {'read': read});
  }

  Future<void> deleteNotification(String notificationId) async {
    await _api.delete('notifications/$notificationId');
  }

  // ---------------- Wallet ----------------

  Future<Map<String, dynamic>> fetchWallet(String userId) async {
    return await _api.get('wallet/$userId') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchMyWallet() async {
    return fetchWallet(_requireUid());
  }

  Future<void> addWalletTransaction({
    required String userId,
    required String type, // credit | debit
    required double amount,
    String description = '',
  }) async {
    await _api.post('wallet/transactions', body: {
      'userId': userId,
      'type': type,
      'amount': amount,
      'description': description,
    });
  }

  Future<void> addMyWalletTransaction({
    required String type,
    required double amount,
    String description = '',
  }) async {
    await addWalletTransaction(
      userId: _requireUid(),
      type: type,
      amount: amount,
      description: description,
    );
  }

  // ---------------- Earnings ----------------

  Future<Map<String, dynamic>> fetchEarnings(String userId) async {
    return await _api.get('earnings/$userId') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchMyEarnings() async {
    return fetchEarnings(_requireUid());
  }

  // ---------------- Reviews ----------------

  Future<List<Map<String, dynamic>>> fetchReviews({String? lawyerId}) async {
    final data = await _api.get('reviews', query: {
      'limit': '100',
      if (lawyerId != null && lawyerId.isNotEmpty) 'lawyerId': lawyerId,
    });
    return (data['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> addReview({
    required String lawyerId,
    required double rating,
    required String comment,
  }) async {
    return await _api.post('reviews', body: {
      'lawyerId': lawyerId,
      'rating': rating,
      'comment': comment,
    }) as Map<String, dynamic>;
  }

  Future<void> deleteReview(String reviewId) async {
    await _api.delete('reviews/$reviewId');
  }

  // ---------------- Chats ----------------

  Future<List<Map<String, dynamic>>> fetchChats() async {
    final data = await _api.get('chats');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> fetchChatMessages(String chatId) async {
    return await _api.get('chats/$chatId') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createChat({
    required List<String> participants,
    Map<String, String>? participantNames,
    String? initialMessage,
  }) async {
    return await _api.post('chats', body: {
      'participants': participants,
      if (participantNames != null) 'participantNames': participantNames,
      if (initialMessage != null && initialMessage.isNotEmpty)
        'lastMessage': initialMessage,
    }) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendMessage({
    required String chatId,
    required String text,
  }) async {
    return await _api.post('chats/$chatId/messages', body: {'text': text})
        as Map<String, dynamic>;
  }

  // ---------------- Supabase Storage and Edge Functions ----------------

  Future<String> uploadLegalDocumentPdf(List<int> bytes) =>
      _api.uploadPrivatePdf(bytes);

  Future<Map<String, dynamic>> _invokeAiAssistant(
    Map<String, dynamic> body,
  ) =>
      _api.invokeSupabaseFunction(AiConfig.edgeFunction, body);

  Future<Map<String, dynamic>> analyzeLegalDocument(String objectPath) async {
    final result = await _invokeAiAssistant(<String, dynamic>{
      'action': 'analyze_document',
      'objectPath': objectPath,
      'consent': true,
    });
    final analysis = result['analysis'];
    if (analysis is! String || analysis.trim().isEmpty) {
      throw ApiException('The AI function returned no document analysis.', 502);
    }
    return <String, dynamic>{
      'analysis': analysis,
      'cleanupRequired': result['cleanup_required'] == true,
    };
  }

  Future<String> predictCaseOutcome({
    required String jurisdiction,
    required String caseType,
    required String description,
    required int precedentWeight,
    required int argumentStrength,
    required int evidenceQuality,
  }) async {
    final result = await _invokeAiAssistant(<String, dynamic>{
      'action': 'predict_case',
      'jurisdiction': jurisdiction,
      'caseType': caseType,
      'description': description,
      'precedentWeight': precedentWeight,
      'argumentStrength': argumentStrength,
      'evidenceQuality': evidenceQuality,
    });
    final prediction = result['prediction'];
    if (prediction is! String || prediction.trim().isEmpty) {
      throw ApiException('The AI function returned no case analysis.', 502);
    }
    return prediction;
  }

  Future<String> askLegalAssistant(String question) async {
    final result = await _invokeAiAssistant(<String, dynamic>{
      'action': 'legal_chat',
      'question': question,
    });
    final answer = result['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw ApiException('The AI function returned no answer.', 502);
    }
    return answer;
  }

  Future<void> deleteTemporaryLegalDocument(String objectPath) =>
      _api.deletePrivatePdf(objectPath);

  // ---------------- Favorites ----------------

  Future<List<Map<String, dynamic>>> fetchFavorites(String userId) async {
    if (_api.usesSupabaseFavorites) {
      final uid = _requireUid();
      final requestedUid = userId.trim();
      if (requestedUid.isNotEmpty && requestedUid != uid) {
        throw ApiException('You can only access your own favorites.', 403);
      }
      // No user_id filter is accepted from the caller: Postgres RLS binds this
      // query to the authenticated profile, including profile-linked legacy IDs.
      final data = await _api.getSupabaseAuthenticatedResource(
        'rest/v1/favorites',
        query: const <String, String>{
          'select': 'id,lawyer_id,created_at',
          'order': 'created_at.desc',
        },
      );
      if (data is! List) {
        throw ApiException.invalidResponse(
          'Supabase returned an unexpected favorites list.',
        );
      }
      final favorites = <Map<String, dynamic>>[];
      for (final row in data) {
        if (row is! Map) {
          throw ApiException.invalidResponse(
            'Supabase returned an invalid favorite record.',
          );
        }
        final id = row['id'];
        final lawyerId = row['lawyer_id'];
        if (id is! String || id.trim().isEmpty ||
            lawyerId is! String || lawyerId.trim().isEmpty) {
          throw ApiException.invalidResponse(
            'Supabase returned an invalid favorite record.',
          );
        }
        favorites.add(<String, dynamic>{
          'id': id,
          'lawyerId': lawyerId,
        });
      }
      return favorites;
    }

    final data = await _api.get('favorites/$userId');
    if (data is! List) {
      throw ApiException.invalidResponse('The favorites response was invalid.');
    }
    try {
      return data.cast<Map<String, dynamic>>();
    } on TypeError {
      throw ApiException.invalidResponse('The favorites response was invalid.');
    }
  }

  /// The signed-in user's favorites, joined with the lawyer documents.
  Future<List<FavoriteEntry>> fetchMyFavorites() async {
    final uid = _requireUid();
    final rows = await fetchFavorites(uid);
    final entries = rows
        .where((row) => (row['lawyerId']?.toString() ?? '').isNotEmpty)
        .toList();

    final joined = await Future.wait(entries.map((row) async {
      final lawyerId = row['lawyerId'].toString();
      final lawyer = await fetchLawyer(lawyerId);
      if (lawyer == null) return null;
      return FavoriteEntry(
        favoriteId: row['id']?.toString() ?? '',
        lawyer: lawyer,
      );
    }));

    return joined.whereType<FavoriteEntry>().toList();
  }

  /// Adds a favorite. The database derives the owner from the verified token.
  Future<String?> addFavorite(String lawyerId) async {
    final safeLawyerId = lawyerId.trim();
    if (safeLawyerId.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(safeLawyerId)) {
      throw ApiException('Invalid lawyer ID.', 400);
    }
    final dynamic result;
    if (_api.usesSupabaseFavorites) {
      _requireUid();
      result = await _api.invokeSupabaseRpc(
        'rpc_favorite_add',
        <String, dynamic>{'p_lawyer_id': safeLawyerId},
      );
    } else {
      result = await _api.post('favorites', body: {'lawyerId': safeLawyerId});
    }
    if (result is Map) {
      final id = result['id']?.toString().trim();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  Future<void> removeFavorite(String favoriteId) async {
    if (_api.usesSupabaseFavorites) {
      _requireUid();
      final safeFavoriteId = favoriteId.trim();
      if (safeFavoriteId.isEmpty ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(safeFavoriteId)) {
        throw ApiException('Invalid favorite ID.', 400);
      }
      final data = await _api.deleteSupabaseAuthenticatedResource(
        'rest/v1/favorites',
        query: <String, String>{'id': 'eq.$safeFavoriteId'},
        returnRepresentation: true,
      );
      if (data is! List || data.isEmpty) {
        throw ApiException('Favorite not found or no longer available.', 404);
      }
      return;
    }
    await _api.delete('favorites/$favoriteId');
  }
}

/// One favorite row joined with the lawyer it points at.
///
/// `favoriteId` is the favorites table row ID used for owner-scoped deletion;
/// `lawyer.id` is the public directory entry.
class FavoriteEntry {
  const FavoriteEntry({required this.favoriteId, required this.lawyer});

  final String favoriteId;
  final Product lawyer;
}
