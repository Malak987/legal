import 'dart:math' as math;

import '../config/ai_config.dart';
import '../models/lawyer_availability.dart';
import '../models/legal_category.dart';
import '../models/paginated_result.dart';
import '../models/product_model.dart';
import 'api_client.dart';

/// Supabase-backed repository for the mobile application's business data.
///
/// Public catalogue queries use the anon key; authenticated records and RPCs
/// use the current user's Auth token and remain subject to database RLS. No
/// mobile workflow falls back to the legacy application API.
class AppRepository {
  AppRepository(this._api);

  final ApiClient _api;

  static const int lawyerPageSize = 20;
  static const int _maxPageSize = 100;
  static const String _publicLawyerColumns =
      'id,category_id,name,specialty,price,price_value,image,rating,location,experience,bio,is_popular,is_top';

  String? get currentUid => _api.currentUid;

  Future<String> _applicationUid() async {
    final profile = await _api.getMyProfile();
    if (profile.uid.isEmpty) {
      throw ApiException('Your Supabase profile is unavailable.', 404);
    }
    return profile.uid;
  }

  // -------------------------------------------------------------------------
  // Public legal catalogue
  // -------------------------------------------------------------------------

  Future<PaginatedResult<Product>> fetchLawyerPage({
    String search = '',
    String? categoryId,
    bool? isPopular,
    bool? isTop,
    int page = 1,
    int limit = lawyerPageSize,
  }) async {
    _validatePage(page, limit);
    final filters = <String, String>{
      'select': _publicLawyerColumns,
      'order': 'rating.desc,name.asc',
      if (categoryId != null && categoryId.trim().isNotEmpty)
        'category_id': 'eq.${_validateId(categoryId, 'category')}',
      if (isPopular != null) 'is_popular': 'eq.$isPopular',
      if (isTop != null) 'is_top': 'eq.$isTop',
    };
    final term = _postgrestSearchTerm(search);
    if (term.isNotEmpty) {
      filters['or'] =
          '(name.ilike.*$term*,specialty.ilike.*$term*,location.ilike.*$term*)';
    }
    final result = await _api.getSupabasePublicLawyerPage(
      query: filters,
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

  Future<List<Product>> fetchLawyers({
    String search = '',
    String? categoryId,
    bool? isPopular,
    bool? isTop,
  }) async =>
      (await fetchLawyerPage(
        search: search,
        categoryId: categoryId,
        isPopular: isPopular,
        isTop: isTop,
        page: 1,
        limit: _maxPageSize,
      ))
          .items;

  Future<Product?> fetchLawyer(String id) async {
    if (id.trim().isEmpty) return null;
    final safeId = _validateId(id, 'lawyer');
    final rows = await _publicRows('lawyers', <String, String>{
      'select': _publicLawyerColumns,
      'id': 'eq.$safeId',
      'limit': '1',
    });
    return rows.isEmpty ? null : _toProduct(rows.first);
  }

  Future<List<LegalCategory>> fetchCategories({String search = ''}) async {
    final filters = <String, String>{
      'select': 'id,name,slug',
      'order': 'name.asc',
      'limit': '100',
    };
    final term = _postgrestSearchTerm(search);
    if (term.isNotEmpty) {
      filters['or'] = '(name.ilike.*$term*,slug.ilike.*$term*)';
    }
    final rows = await _publicRows('legal_categories', filters);
    final categories = rows.map(LegalCategory.fromJson).toList(growable: false);
    if (categories.any((category) => category.id.isEmpty || category.name.isEmpty)) {
      throw ApiException.invalidResponse('The category list contained an invalid record.');
    }
    return categories;
  }

  Future<List<LawyerAvailability>> fetchAvailability(String lawyerId) async {
    final safeId = _validateId(lawyerId, 'lawyer');
    final rows = await _publicRows('availability', <String, String>{
      'select': 'id,lawyer_id,date,slots',
      'lawyer_id': 'eq.$safeId',
      'order': 'date.asc',
      'limit': '100',
    });
    return rows
        .map(LawyerAvailability.fromJson)
        .toList(growable: false);
  }

  Product _toProduct(Map<String, dynamic> row) {
    final id = _asString(row['id'], 'lawyer ID');
    final name = _asString(row['name'], 'lawyer name');
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw ApiException.invalidResponse('The lawyer response omitted a required ID or name.');
    }
    return Product(
      id: id,
      imagePath: _optionalString(row['image'], 'image') ?? '',
      name: name,
      price: _optionalString(row['price'], 'price') ?? '',
      specialty: _optionalString(row['specialty'], 'specialty'),
      categoryId: _optionalString(row['category_id'] ?? row['categoryId'], 'category ID'),
      rating: _optionalNumber(row['rating'], 'rating'),
      location: _optionalString(row['location'], 'location'),
      priceValue: _optionalNumber(row['price_value'] ?? row['priceValue'], 'price value'),
      experience: _optionalString(row['experience'], 'experience'),
      bio: _optionalString(row['bio'], 'bio'),
      isPopular: _optionalBool(row['is_popular'] ?? row['isPopular'], 'popular flag'),
      isTop: _optionalBool(row['is_top'] ?? row['isTop'], 'top flag'),
    );
  }

  // -------------------------------------------------------------------------
  // Cases and tasks
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchMyCases() => _authenticatedRows(
        'cases',
        <String, String>{
          'select':
              'id,user_id,title,description,client_name,case_type,priority,status,due_date,lawyer_id,category_id,created_at,updated_at',
          'order': 'updated_at.desc',
        },
      );

  Future<Map<String, dynamic>> fetchCase(String caseId) async {
    final id = _validateId(caseId, 'case');
    final rows = await _authenticatedRows('cases', <String, String>{
      'select':
          'id,user_id,title,description,client_name,case_type,priority,status,due_date,lawyer_id,category_id,created_at,updated_at',
      'id': 'eq.$id',
      'limit': '1',
    });
    if (rows.isEmpty) throw ApiException('Case not found.', 404);
    return rows.first;
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
    final uid = await _applicationUid();
    final cleanTitle = title.trim();
    if (cleanTitle.length < 2) throw ApiException('Enter a case title.', 400);
    final safeCategoryId = categoryId == null || categoryId.trim().isEmpty
        ? null
        : _validateId(categoryId, 'category');
    final safeLawyerId = lawyerId == null || lawyerId.trim().isEmpty
        ? null
        : _validateId(lawyerId, 'lawyer');
    if ((safeCategoryId == null) != (safeLawyerId == null)) {
      throw ApiException('Select both a category and lawyer, or leave both unassigned.', 400);
    }
    final response = await _api.postSupabaseAuthenticatedResource(
      'rest/v1/cases',
      query: const <String, String>{
        'select':
            'id,user_id,title,description,client_name,case_type,priority,status,due_date,lawyer_id,category_id,created_at,updated_at',
      },
      body: <String, dynamic>{
        'user_id': uid,
        'title': cleanTitle,
        'description': description.trim(),
        'client_name': clientName.trim(),
        'case_type': caseType.trim().isEmpty ? 'General' : caseType.trim(),
        'priority': priority,
        'due_date': dueDate,
        if (safeCategoryId != null) 'category_id': safeCategoryId,
        if (safeLawyerId != null) 'lawyer_id': safeLawyerId,
      },
    );
    return _expectRow(response, 'case creation');
  }

  Future<Map<String, dynamic>> updateCase(
    String caseId,
    Map<String, dynamic> changes,
  ) async {
    final id = _validateId(caseId, 'case');
    final safeChanges = _snakeCaseKeys(changes);
    final response = await _api.invokeSupabaseRpc('rpc_case_update', <String, dynamic>{
      'p_case_id': id,
      'p_changes': safeChanges,
    });
    return _expectRow(response, 'case update');
  }

  Future<void> deleteCase(String caseId) async {
    final id = _validateId(caseId, 'case');
    final response = await _api.deleteSupabaseAuthenticatedResource(
      'rest/v1/cases',
      query: <String, String>{'id': 'eq.$id'},
      returnRepresentation: true,
    );
    if (response is! List || response.isEmpty) throw ApiException('Case not found.', 404);
  }

  Future<List<Map<String, dynamic>>> fetchTasks() => _authenticatedRows(
        'tasks',
        const <String, String>{
          'select':
              'id,user_id,title,description,due_date,priority,status,created_at,updated_at',
          'order': 'created_at.desc',
        },
      );

  Future<Map<String, dynamic>> createTask({
    required String title,
    String description = '',
    String dueDate = '',
    String priority = 'Medium',
    String status = 'Pending',
  }) async {
    final uid = await _applicationUid();
    final response = await _api.postSupabaseAuthenticatedResource(
      'rest/v1/tasks',
      query: const <String, String>{
        'select':
            'id,user_id,title,description,due_date,priority,status,created_at,updated_at',
      },
      body: <String, dynamic>{
        'user_id': uid,
        'title': title.trim(),
        'description': description.trim(),
        'due_date': dueDate,
        'priority': priority,
        'status': status,
      },
    );
    return _expectRow(response, 'task creation');
  }

  Future<Map<String, dynamic>> updateTask(
    String taskId,
    Map<String, dynamic> updates,
  ) async {
    final id = _validateId(taskId, 'task');
    final response = await _api.invokeSupabaseRpc('rpc_task_update', <String, dynamic>{
      'p_task_id': id,
      'p_changes': _snakeCaseKeys(updates),
    });
    return _expectRow(response, 'task update');
  }

  Future<void> deleteTask(String taskId) async {
    final id = _validateId(taskId, 'task');
    final response = await _api.deleteSupabaseAuthenticatedResource(
      'rest/v1/tasks',
      query: <String, String>{'id': 'eq.$id'},
      returnRepresentation: true,
    );
    if (response is! List || response.isEmpty) throw ApiException('Task not found.', 404);
  }

  // -------------------------------------------------------------------------
  // Bookings
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchBookings({String? status}) {
    final safeStatus = status?.trim();
    if (safeStatus != null &&
        safeStatus.isNotEmpty &&
        !const {'Pending', 'Confirmed', 'Completed', 'Cancelled', 'Active'}
            .contains(safeStatus)) {
      throw ApiException('Invalid booking status filter.', 400);
    }
    return _authenticatedRows('bookings', <String, String>{
      'select':
          'id,user_id,lawyer_id,lawyer_name,date,time,hours,total_price,status,created_at,updated_at',
      'order': 'created_at.desc',
      if (safeStatus != null && safeStatus.isNotEmpty) 'status': 'eq.$safeStatus',
    });
  }

  Future<Map<String, dynamic>> createBooking({
    required String lawyerId,
    required String lawyerName,
    required String date,
    required String time,
    required int hours,
    double totalPrice = 0,
    String? idempotencyKey,
  }) async {
    final safeId = _validateId(lawyerId, 'lawyer');
    final key = idempotencyKey?.trim().isNotEmpty == true
        ? idempotencyKey!.trim()
        : _newIdempotencyKey();
    final response = await _api.invokeSupabaseRpc('rpc_create_booking', <String, dynamic>{
      'p_lawyer_id': safeId,
      'p_date': date,
      'p_time': time,
      'p_hours': hours,
      'p_idempotency_key': key,
      'p_user_id': null,
    });
    final outcome = _expectRow(response, 'booking creation');
    final booking = outcome['booking'];
    if (booking is Map) return _camelizeMap(booking);
    // Keep compatibility with an older JSON-RPC version that returned the row
    // directly; the current transaction returns it inside `booking`.
    return outcome;
  }

  Future<void> updateBookingStatus(String bookingId, String status) async {
    final id = _validateId(bookingId, 'booking');
    if (status != 'Cancelled') {
      throw ApiException('Only a booking cancellation is available in the mobile app.', 403);
    }
    _expectRow(
      await _api.invokeSupabaseRpc('rpc_cancel_booking', <String, dynamic>{
        'p_booking_id': id,
      }),
      'booking cancellation',
    );
  }

  // -------------------------------------------------------------------------
  // Plans and subscriptions
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchPlans() => _publicRows(
        'plans',
        const <String, String>{
          'select': 'id,title,price,price_value,color,features,is_popular',
          'order': 'price_value.asc',
          'limit': '100',
        },
      );

  Future<List<Map<String, dynamic>>> fetchMySubscriptions() => _authenticatedRows(
        'subscriptions',
        const <String, String>{
          'select': 'id,user_id,plan_id,plan_title,status,start_date,end_date,created_at,updated_at',
          'order': 'created_at.desc',
        },
      );

  Future<Map<String, dynamic>> createSubscription({
    required String planId,
    String? userId,
  }) async {
    final plan = _validateId(planId, 'plan');
    final uid = await _applicationUid();
    if (userId != null && userId.trim().isNotEmpty && userId.trim() != uid) {
      throw ApiException('You can only subscribe your own account.', 403);
    }
    final response = await _api.invokeSupabaseRpc('rpc_subscription_create', <String, dynamic>{
      'p_plan_id': plan,
      // No caller-supplied recipient: the RPC derives the authenticated owner.
      'p_user_id': null,
    });
    return _expectRow(response, 'subscription creation');
  }

  Future<Map<String, dynamic>> cancelSubscription(String subscriptionId) async {
    final id = _validateId(subscriptionId, 'subscription');
    final response = await _api.invokeSupabaseRpc(
      'rpc_subscription_cancel',
      <String, dynamic>{'p_subscription_id': id},
    );
    return _expectRow(response, 'subscription cancellation');
  }

  // -------------------------------------------------------------------------
  // Notifications
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchNotifications(String userId) async {
    final requested = userId.trim();
    if (requested.isEmpty) throw ApiException('A user ID is required.', 400);
    final profile = await _api.getMyProfile();
    if (!profile.isAdmin && requested != profile.uid) {
      throw ApiException('You can only access your own notifications.', 403);
    }
    return _authenticatedRows('notifications', <String, String>{
      'select': 'id,user_id,title,content,type,icon,read,created_at,updated_at',
      'user_id': 'eq.$requested',
      'order': 'created_at.desc',
    });
  }

  Future<List<Map<String, dynamic>>> fetchMyNotifications() async =>
      fetchNotifications(await _applicationUid());

  Future<Map<String, dynamic>> markNotificationRead(
    String notificationId,
    bool read,
  ) async {
    final id = _validateId(notificationId, 'notification');
    final response = await _api.invokeSupabaseRpc('rpc_notification_update', <String, dynamic>{
      'p_notification_id': id,
      'p_changes': <String, dynamic>{'read': read},
    });
    return _expectRow(response, 'notification update');
  }

  Future<void> deleteNotification(String notificationId) async {
    final id = _validateId(notificationId, 'notification');
    final response = await _api.deleteSupabaseAuthenticatedResource(
      'rest/v1/notifications',
      query: <String, String>{'id': 'eq.$id'},
      returnRepresentation: true,
    );
    if (response is! List || response.isEmpty) {
      throw ApiException('Notification not found.', 404);
    }
  }

  // -------------------------------------------------------------------------
  // Wallet and earnings
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> fetchWallet(String userId) async {
    final requested = _validateId(userId, 'user');
    final profile = await _api.getMyProfile();
    if (!profile.isAdmin && requested != profile.uid) {
      throw ApiException('You can only access your own wallet.', 403);
    }
    final walletRows = await _authenticatedRows('wallets', <String, String>{
      'select': 'id,user_id,balance,currency,created_at,updated_at',
      'user_id': 'eq.$requested',
      'limit': '1',
    });
    final transactionRows = await _authenticatedRows('wallet_transactions', <String, String>{
      'select': 'id,user_id,type,amount,description,balance,currency,created_at',
      'user_id': 'eq.$requested',
      'order': 'created_at.desc',
      'limit': '20',
    });
    final wallet = walletRows.isEmpty ? <String, dynamic>{} : walletRows.first;
    return <String, dynamic>{
      ...wallet,
      'balance': wallet['balance'] ?? 0,
      'currency': wallet['currency'] ?? 'USD',
      'transactions': transactionRows,
    };
  }

  Future<Map<String, dynamic>> fetchMyWallet() async =>
      fetchWallet(await _applicationUid());

  Future<void> addWalletTransaction({
    required String userId,
    required String type,
    required double amount,
    String description = '',
    String? idempotencyKey,
  }) async {
    if (type != 'credit' && type != 'debit') {
      throw ApiException('Invalid wallet transaction type.', 400);
    }
    final user = _validateId(userId, 'user');
    final key = idempotencyKey?.trim().isNotEmpty == true
        ? idempotencyKey!.trim()
        : _newIdempotencyKey();
    final result = await _api.invokeSupabaseRpc('rpc_wallet_mutate', <String, dynamic>{
      'p_user_id': user,
      'p_type': type,
      'p_amount': amount,
      'p_description': description.trim(),
      'p_idempotency_id': key,
    });
    final row = _expectRow(result, 'wallet transaction');
    if (!row.containsKey('balance') || row['transaction'] is! Map) {
      throw ApiException.invalidResponse('The wallet transaction response was incomplete.');
    }
  }

  Future<void> addMyWalletTransaction({
    required String type,
    required double amount,
    String description = '',
    String? idempotencyKey,
  }) async {
    await addWalletTransaction(
      userId: await _applicationUid(),
      type: type,
      amount: amount,
      description: description,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<Map<String, dynamic>> fetchEarnings(String userId) async {
    final requested = _validateId(userId, 'user');
    final profile = await _api.getMyProfile();
    if (!profile.isAdmin && requested != profile.uid) {
      throw ApiException('You can only access your own earnings.', 403);
    }
    final rows = await _authenticatedRows('earnings', <String, String>{
      'select': 'id,user_id,balance,total_earnings,breakdown,created_at,updated_at',
      'user_id': 'eq.$requested',
      'limit': '1',
    });
    if (rows.isEmpty) throw ApiException('No earnings record found.', 404);
    final row = rows.first;
    final breakdown = row['breakdown'];
    final history = breakdown is Map && breakdown['history'] is List
        ? (breakdown['history'] as List)
            .whereType<Map>()
            .map((entry) => _camelizeMap(entry))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    return <String, dynamic>{
      ...row,
      'pendingPayout': row['balance'] ?? 0,
      'totalEarnings': row['totalEarnings'] ?? 0,
      'history': history,
    };
  }

  Future<Map<String, dynamic>> fetchMyEarnings() async =>
      fetchEarnings(await _applicationUid());

  // -------------------------------------------------------------------------
  // Reviews
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchReviews({String? lawyerId}) async {
    final safeId = lawyerId == null || lawyerId.trim().isEmpty
        ? null
        : _validateId(lawyerId, 'lawyer');
    return _publicRows('public_reviews', <String, String>{
      'select': 'id,user_name,lawyer_id,rating,comment,created_at,updated_at',
      'order': 'created_at.desc',
      'limit': '100',
      if (safeId != null) 'lawyer_id': 'eq.$safeId',
    });
  }

  Future<Map<String, dynamic>> addReview({
    required String lawyerId,
    required double rating,
    required String comment,
  }) async {
    final safeId = _validateId(lawyerId, 'lawyer');
    final result = await _api.invokeSupabaseRpc('rpc_review_submit', <String, dynamic>{
      'p_lawyer_id': safeId,
      'p_rating': rating,
      'p_comment': comment.trim(),
    });
    return _expectRow(result, 'review submission');
  }

  Future<void> deleteReview(String reviewId) async {
    final id = _validateId(reviewId, 'review');
    _expectRow(
      await _api.invokeSupabaseRpc('rpc_review_delete', <String, dynamic>{
        'p_review_id': id,
      }),
      'review deletion',
    );
  }

  // -------------------------------------------------------------------------
  // Chat
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchChats() => _authenticatedRows(
        'chats',
        const <String, String>{
          'select': 'id,participants,participant_names,last_message,created_at,updated_at',
          'order': 'updated_at.desc',
        },
      );

  Future<Map<String, dynamic>> fetchChatMessages(String chatId) async {
    final id = _validateId(chatId, 'chat');
    final chats = await _authenticatedRows('chats', <String, String>{
      'select': 'id,participants,participant_names,last_message,created_at,updated_at',
      'id': 'eq.$id',
      'limit': '1',
    });
    if (chats.isEmpty) throw ApiException('Chat not found.', 404);
    final messages = await _authenticatedRows('chat_messages', <String, String>{
      'select': 'id,chat_id,sender_id,sender_name,text,created_at',
      'chat_id': 'eq.$id',
      'order': 'created_at.asc',
    });
    return <String, dynamic>{...chats.first, 'messages': messages};
  }

  Future<Map<String, dynamic>> createChat({
    required List<String> participants,
    Map<String, String>? participantNames,
    String? initialMessage,
  }) async {
    final uid = await _applicationUid();
    final unique = participants
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (!unique.contains(uid)) unique.add(uid);
    for (final userId in unique) {
      _validateId(userId, 'chat participant');
    }
    if (unique.length < 2) {
      throw ApiException('A conversation needs at least one other participant.', 400);
    }
    final result = await _api.invokeSupabaseRpc('rpc_chat_create', <String, dynamic>{
      'p_participants': unique,
      'p_initial_message': initialMessage?.trim().isNotEmpty == true
          ? initialMessage!.trim()
          : null,
    });
    final row = _expectRow(result, 'chat creation');
    final chat = row['chat'];
    if (chat is! Map) throw ApiException.invalidResponse('The chat response was incomplete.');
    return _camelizeMap(chat);
  }

  Future<Map<String, dynamic>> sendMessage({
    required String chatId,
    required String text,
  }) async {
    final id = _validateId(chatId, 'chat');
    final response = await _api.invokeSupabaseRpc('rpc_chat_send_message', <String, dynamic>{
      'p_chat_id': id,
      'p_text': text.trim(),
    });
    return _expectRow(response, 'message send');
  }

  // -------------------------------------------------------------------------
  // Storage and trusted Edge Functions
  // -------------------------------------------------------------------------

  Future<String> uploadLegalDocumentPdf(List<int> bytes) => _api.uploadPrivatePdf(bytes);

  Future<Map<String, dynamic>> _invokeAiAssistant(Map<String, dynamic> body) =>
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

  // -------------------------------------------------------------------------
  // Favorites
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchFavorites(String userId) async {
    final requested = userId.trim();
    if (requested.isEmpty) throw ApiException('A user ID is required.', 400);
    final profile = await _api.getMyProfile();
    if (!profile.isAdmin && requested != profile.uid) {
      throw ApiException('You can only access your own favorites.', 403);
    }
    return _authenticatedRows('favorites', <String, String>{
      'select': 'id,user_id,lawyer_id,created_at',
      'user_id': 'eq.$requested',
      'order': 'created_at.desc',
    });
  }

  Future<List<FavoriteEntry>> fetchMyFavorites() async {
    final uid = await _applicationUid();
    final rows = await fetchFavorites(uid);
    final joined = await Future.wait(rows.map((row) async {
      final lawyer = await fetchLawyer((row['lawyer_id'] ?? row['lawyerId'])?.toString() ?? '');
      if (lawyer == null) return null;
      return FavoriteEntry(
        favoriteId: row['id']?.toString() ?? '',
        lawyer: lawyer,
      );
    }));
    return joined.whereType<FavoriteEntry>().toList(growable: false);
  }

  Future<String?> addFavorite(String lawyerId) async {
    final id = _validateId(lawyerId, 'lawyer');
    final response = await _api.invokeSupabaseRpc('rpc_favorite_add', <String, dynamic>{
      'p_lawyer_id': id,
    });
    final row = _expectRow(response, 'favorite creation');
    final favoriteId = row['id']?.toString().trim();
    return favoriteId == null || favoriteId.isEmpty ? null : favoriteId;
  }

  Future<void> removeFavorite(String favoriteId) async {
    final id = _validateId(favoriteId, 'favorite');
    final result = await _api.deleteSupabaseAuthenticatedResource(
      'rest/v1/favorites',
      query: <String, String>{'id': 'eq.$id'},
      returnRepresentation: true,
    );
    if (result is! List || result.isEmpty) {
      throw ApiException('Favorite not found or no longer available.', 404);
    }
  }

  // -------------------------------------------------------------------------
  // Shared PostgREST and wire-format helpers
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _publicRows(
    String table,
    Map<String, String> query,
  ) async {
    final data = await _api.getSupabasePublicResource(table, query: query);
    return _mapRows(data, '$table catalogue');
  }

  Future<List<Map<String, dynamic>>> _authenticatedRows(
    String table,
    Map<String, String> query,
  ) async {
    final result = await _api.getSupabaseAuthenticatedPage(
      table,
      query: query,
      page: 1,
      limit: _maxPageSize,
    );
    return result.items.map(_camelizeMap).toList(growable: false);
  }

  List<Map<String, dynamic>> _mapRows(dynamic value, String label) {
    if (value is! List) {
      throw ApiException.invalidResponse('Supabase returned an invalid $label response.');
    }
    final rows = <Map<String, dynamic>>[];
    for (final item in value) {
      if (item is! Map) {
        throw ApiException.invalidResponse('Supabase returned an invalid $label record.');
      }
      rows.add(_camelizeMap(item));
    }
    return rows;
  }

  Map<String, dynamic> _expectRow(dynamic response, String operation) {
    dynamic value = response;
    if (value is List) {
      if (value.isEmpty) {
        throw ApiException.invalidResponse('Supabase returned no row for $operation.');
      }
      value = value.first;
    }
    if (value is! Map) {
      throw ApiException.invalidResponse('Supabase returned an invalid $operation response.');
    }
    final row = _camelizeMap(value);
    final error = row['error'];
    if (error is String && error.isNotEmpty) throw _domainError(error);
    return row;
  }

  ApiException _domainError(String code) {
    switch (code) {
      case 'SLOT_TAKEN':
        return ApiException('That appointment time was just booked. Choose another time.', 409);
      case 'NO_AVAILABILITY':
      case 'TIME_NOT_AVAILABLE':
        return ApiException('The lawyer is not available at that time.', 409);
      case 'INSUFFICIENT_FUNDS':
        return ApiException('Your wallet balance is too low for this transaction.', 400);
      case 'WALLET_OPERATION_NOT_AUTHORIZED':
        return ApiException('Wallet credits require verified administrator or payment approval.', 403);
      case 'DUPLICATE_REVIEW':
        return ApiException('You have already reviewed this lawyer.', 409);
      case 'IDEMPOTENCY_KEY_MISMATCH':
        return ApiException('This request key was already used for different details.', 409);
      case 'UNKNOWN_PLAN':
      case 'UNKNOWN_USER':
      case 'LAWYER_NOT_FOUND':
        return ApiException('The requested record is no longer available.', 404);
      case 'INVALID_BOOKING_DATE':
      case 'INVALID_BOOKING_TIME':
      case 'INVALID_BOOKING_DURATION':
      case 'INVALID_TRANSACTION':
      case 'INVALID_REVIEW':
        return ApiException('Some submitted details are invalid. Review them and try again.', 400);
      default:
        return ApiException('Supabase could not complete $code.', 400);
    }
  }

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

  String _validateId(String value, String label) {
    final id = value.trim();
    if (id.isEmpty || id.length > 200 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw ApiException('Invalid $label ID.', 400);
    }
    return id;
  }

  void _validatePage(int page, int limit) {
    if (page < 1 || limit < 1 || limit > _maxPageSize) {
      throw ApiException('Invalid page request.', 400);
    }
  }

  String _newIdempotencyKey() {
    final random = math.Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(16))
        .map((value) => value.toRadixString(16))
        .join();
  }

  Map<String, dynamic> _snakeCaseKeys(Map<String, dynamic> input) {
    final allowed = <String, String>{
      'title': 'title',
      'description': 'description',
      'clientName': 'client_name',
      'caseType': 'case_type',
      'priority': 'priority',
      'dueDate': 'due_date',
      'status': 'status',
      'userId': 'user_id',
      'read': 'read',
      'content': 'content',
      'type': 'type',
    };
    final result = <String, dynamic>{};
    for (final entry in input.entries) {
      final key = allowed[entry.key] ?? entry.key;
      result[key] = entry.value;
    }
    return result;
  }

  String _asString(dynamic value, String field) {
    if (value is String) return value;
    throw ApiException.invalidResponse('Supabase returned an invalid $field.');
  }

  String? _optionalString(dynamic value, String field) {
    if (value == null) return null;
    if (value is String) return value;
    throw ApiException.invalidResponse('Supabase returned an invalid $field.');
  }

  double? _optionalNumber(dynamic value, String field) {
    if (value == null) return null;
    if (value is num && value.isFinite) return value.toDouble();
    throw ApiException.invalidResponse('Supabase returned an invalid $field.');
  }

  bool? _optionalBool(dynamic value, String field) {
    if (value == null) return null;
    if (value is bool) return value;
    throw ApiException.invalidResponse('Supabase returned an invalid $field.');
  }
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

/// One favorite row joined with the public lawyer directory entry it points at.
class FavoriteEntry {
  const FavoriteEntry({required this.favoriteId, required this.lawyer});

  final String favoriteId;
  final Product lawyer;
}
