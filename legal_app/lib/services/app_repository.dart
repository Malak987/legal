import '../models/product_model.dart';
import 'api_client.dart';

/// Repository that fetches the app's data from the backend REST API.
///
/// This replaces the hard-coded lists (ProductData, sample case lists, etc.)
/// so the screens can show live data stored in Firestore.
class AppRepository {
  AppRepository(this._api);
  final ApiClient _api;

  // ---------------- Lawyers ----------------

  /// Fetches lawyers, optionally filtered to popular or top-rated ones.
  Future<List<Product>> fetchLawyers({
    String search = '',
    bool? isPopular,
    bool? isTop,
  }) async {
    final data = await _api.get('lawyers', query: {
      'limit': '100',
      if (search.isNotEmpty) 'search': search,
      if (isPopular != null) 'isPopular': '$isPopular',
      if (isTop != null) 'isTop': '$isTop',
    });

    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(_toProduct).toList();
  }

  /// Fetches a single lawyer, or `null` when the document is gone.
  Future<Product?> fetchLawyer(String id) async {
    if (id.isEmpty) return null;
    try {
      final data = await _api.get('lawyers/$id');
      return _toProduct(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  Product _toProduct(Map<String, dynamic> json) {
    return Product(
      id: json['id']?.toString(),
      imagePath: json['image']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      price: json['price']?.toString() ?? '',
      specialty: json['specialty']?.toString(),
      rating: (json['rating'] as num?)?.toDouble(),
      location: json['location']?.toString(),
    );
  }

  // ---------------- Cases ----------------

  Future<List<Map<String, dynamic>>> fetchMyCases() async {
    final data = await _api.get('cases', query: {'limit': '100'});
    return (data['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createCase({
    required String title,
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

  // ---------------- Plans ----------------

  Future<List<Map<String, dynamic>>> fetchPlans() async {
    final data = await _api.get('plans', query: {'limit': '100'});
    return (data['items'] as List).cast<Map<String, dynamic>>();
  }

  // ---------------- Notifications ----------------

  Future<List<Map<String, dynamic>>> fetchNotifications(String userId) async {
    final data = await _api.get('notifications/$userId', query: {'limit': '100'});
    return (data['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> markNotificationRead(String notificationId, bool read) async {
    await _api.put('notifications/$notificationId/read', body: {'read': read});
  }

  // ---------------- Wallet ----------------

  Future<Map<String, dynamic>> fetchWallet(String userId) async {
    return await _api.get('wallet/$userId') as Map<String, dynamic>;
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

  // ---------------- Earnings ----------------

  Future<Map<String, dynamic>> fetchEarnings(String userId) async {
    return await _api.get('earnings/$userId') as Map<String, dynamic>;
  }

  // ---------------- Reviews ----------------

  Future<List<Map<String, dynamic>>> fetchReviews({String? lawyerId}) async {
    final data = await _api.get('reviews', query: {
      'limit': '100',
      if (lawyerId != null) 'lawyerId': lawyerId,
    });
    return (data['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> addReview({
    required String lawyerId,
    required double rating,
    required String comment,
  }) async {
    await _api.post('reviews', body: {
      'lawyerId': lawyerId,
      'rating': rating,
      'comment': comment,
    });
  }

  // ---------------- Chats ----------------

  Future<List<Map<String, dynamic>>> fetchChats() async {
    final data = await _api.get('chats');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> fetchChatMessages(String chatId) async {
    return await _api.get('chats/$chatId') as Map<String, dynamic>;
  }

  Future<void> sendMessage({
    required String chatId,
    required String text,
  }) async {
    await _api.post('chats/$chatId/messages', body: {'text': text});
  }

  // ---------------- Favorites ----------------

  Future<List<Map<String, dynamic>>> fetchFavorites(String userId) async {
    final data = await _api.get('favorites/$userId');
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// The signed-in user's favorites, joined with the lawyer documents.
  ///
  /// `GET /api/favorites/:userId` returns rows that only carry `lawyerId`, so
  /// each lawyer is fetched separately. A favorite whose lawyer was deleted is
  /// skipped rather than rendered as an empty card — the backend does not
  /// check that the lawyer still exists when the favorite is created.
  Future<List<FavoriteEntry>> fetchMyFavorites() async {
    final uid = _api.currentUid;
    if (uid == null || uid.isEmpty) {
      throw ApiException('You are not signed in.', 401);
    }

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

  /// Adds a favorite. The owner comes from the verified token, so no uid is
  /// sent — the backend ignores one anyway.
  Future<void> addFavorite(String lawyerId) async {
    await _api.post('favorites', body: {'lawyerId': lawyerId});
  }

  Future<void> removeFavorite(String favoriteId) async {
    await _api.delete('favorites/$favoriteId');
  }
}

/// One favorite row joined with the lawyer it points at.
///
/// `favoriteId` is the `favorites/{id}` document, which is what the delete
/// endpoint needs; `lawyer.id` is the directory entry.
class FavoriteEntry {
  const FavoriteEntry({required this.favoriteId, required this.lawyer});

  final String favoriteId;
  final Product lawyer;
}
