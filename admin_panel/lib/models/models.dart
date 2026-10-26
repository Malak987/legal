/// Plain Dart models used by the admin panel.
/// All models can be created from the JSON returned by the backend API.
library;

class LegalCategory {
  final String id;
  final String name;
  final String slug;

  const LegalCategory({required this.id, required this.name, this.slug = ''});

  factory LegalCategory.fromJson(Map<String, dynamic> json) => LegalCategory(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        slug: json['slug']?.toString() ?? '',
      );
}

class Lawyer {
  final String id;
  final String name;
  final String userId;
  final String specialty;
  final String experience;
  final String categoryId;
  final String price;

  /// Numeric hourly rate, in the same currency as the wallet (USD).
  ///
  /// The backend prices a booking as `priceValue * hours`, so a lawyer without
  /// this field cannot be booked at all. `null` means "not configured" (legacy
  /// records and anything created before the field existed).
  final double? priceValue;
  final String image;
  final double rating;
  final String location;
  final String bio;
  final bool isPopular;
  final bool isTop;

  Lawyer({
    required this.id,
    required this.name,
    this.userId = '',
    this.specialty = '',
    this.experience = '',
    this.categoryId = '',
    this.price = '',
    this.priceValue,
    this.image = '',
    this.rating = 0,
    this.location = '',
    this.bio = '',
    this.isPopular = false,
    this.isTop = false,
  });

  factory Lawyer.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['priceValue'];
    return Lawyer(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      specialty: json['specialty']?.toString() ?? '',
      experience: json['experience']?.toString() ?? '',
      categoryId: json['categoryId']?.toString() ?? json['category_id']?.toString() ?? '',
      price: json['price']?.toString() ?? '',
      priceValue: rawPrice is num ? rawPrice.toDouble() : null,
      image: json['image']?.toString() ?? '',
      rating: (json['rating'] ?? 0).toDouble(),
      location: json['location']?.toString() ?? '',
      bio: json['bio']?.toString() ?? '',
      isPopular: json['isPopular'] == true,
      isTop: json['isTop'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (userId.isNotEmpty) 'userId': userId,
        'specialty': specialty,
        'experience': experience,
        if (categoryId.isNotEmpty) 'categoryId': categoryId,
        'price': price,
        if (priceValue != null) 'priceValue': priceValue,
        'image': image,
        'rating': rating,
        'location': location,
        'bio': bio,
        'isPopular': isPopular,
        'isTop': isTop,
      };
}

class AppUser {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String avatar;
  final String address;

  /// Whether the source document actually declared a `role`.
  ///
  /// [AppUser.fromJson] falls back to `'client'` so that older records still
  /// render, but that fallback is **not** evidence that the account is a
  /// client. The backend rejects a case owned by a non-client
  /// (`CASE_OWNER_ROLES` in `backend/src/routes/cases.js`), so anything that
  /// offers or accepts a client must check [isClient] rather than [role].
  ///
  /// Defaults to `true` for objects built in code, where the role is known.
  final bool hasExplicitRole;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone = '',
    this.role = 'client',
    this.avatar = '',
    this.address = '',
    this.hasExplicitRole = true,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final rawRole = json['role'];
    return AppUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      role: rawRole?.toString() ?? 'client',
      avatar: json['avatar']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      hasExplicitRole: rawRole != null && rawRole.toString().isNotEmpty,
    );
  }

  /// True only when the payload explicitly says `role: 'client'`.
  bool get isClient => hasExplicitRole && role == 'client';

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'phone': phone,
        'role': role,
        'avatar': avatar,
        'address': address,
      };
}

class CaseItem {
  final String id;
  final String title;
  final String description;
  final String clientName;
  final String caseType;
  final String priority;
  final String status;
  final String dueDate;
  final String userId;
  final String lawyerId;
  final String categoryId;
  final String lawyerName;
  final String categoryName;

  CaseItem({
    required this.id,
    required this.title,
    this.description = '',
    this.clientName = '',
    this.caseType = '',
    this.priority = 'Medium',
    this.status = 'Open',
    this.dueDate = '',
    this.userId = '',
    this.lawyerId = '',
    this.categoryId = '',
    this.lawyerName = '',
    this.categoryName = '',
  });

  factory CaseItem.fromJson(Map<String, dynamic> json) {
    return CaseItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      clientName: json['clientName']?.toString() ?? '',
      caseType: json['caseType']?.toString() ?? '',
      priority: json['priority']?.toString() ?? 'Medium',
      status: json['status']?.toString() ?? 'Open',
      dueDate: json['dueDate']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      lawyerId: json['lawyerId']?.toString() ?? '',
      categoryId: json['categoryId']?.toString() ?? '',
      lawyerName: json['lawyerName']?.toString() ?? '',
      categoryName: json['categoryName']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'clientName': clientName,
        'caseType': caseType,
        'priority': priority,
        'status': status,
        'dueDate': dueDate,
        if (userId.isNotEmpty) 'userId': userId,
        if (lawyerId.isNotEmpty) 'lawyerId': lawyerId,
        if (categoryId.isNotEmpty) 'categoryId': categoryId,
      };
}

class Booking {
  final String id;
  final String lawyerName;
  final String date;
  final String time;
  final int hours;
  final double totalPrice;
  final String status;
  final String userId;
  final String lawyerId;

  Booking({
    required this.id,
    this.lawyerName = '',
    this.date = '',
    this.time = '',
    this.hours = 1,
    this.totalPrice = 0,
    this.status = 'Pending',
    this.userId = '',
    this.lawyerId = '',
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['id']?.toString() ?? '',
      lawyerName: json['lawyerName']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      hours: (json['hours'] ?? 1) is int
          ? json['hours']
          : int.tryParse('${json['hours']}') ?? 1,
      totalPrice: (json['totalPrice'] ?? 0).toDouble(),
      status: json['status']?.toString() ?? 'Pending',
      userId: json['userId']?.toString() ?? '',
      lawyerId: json['lawyerId']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'lawyerName': lawyerName,
        'date': date,
        'time': time,
        'hours': hours,
        'totalPrice': totalPrice,
        'status': status,
        if (lawyerId.isNotEmpty) 'lawyerId': lawyerId,
        if (userId.isNotEmpty) 'userId': userId,
      };
}

class Review {
  final String id;
  final String userName;
  final double rating;
  final String comment;
  final String lawyerId;
  final String userId;

  Review({
    required this.id,
    this.userName = '',
    this.rating = 0,
    this.comment = '',
    this.lawyerId = '',
    this.userId = '',
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id']?.toString() ?? '',
      userName: json['userName']?.toString() ?? '',
      rating: (json['rating'] ?? 0).toDouble(),
      comment: json['comment']?.toString() ?? '',
      lawyerId: json['lawyerId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'userName': userName,
        'rating': rating,
        'comment': comment,
        if (lawyerId.isNotEmpty) 'lawyerId': lawyerId,
        if (userId.isNotEmpty) 'userId': userId,
      };
}

class Plan {
  final String id;
  final String title;
  final String price;
  final String color;
  final List<String> features;
  final bool isPopular;

  Plan({
    required this.id,
    required this.title,
    this.price = '',
    this.color = '#3498DB',
    this.features = const [],
    this.isPopular = false,
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      price: json['price']?.toString() ?? '',
      color: json['color']?.toString() ?? '#3498DB',
      features: (json['features'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isPopular: json['isPopular'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'price': price,
        'color': color,
        'features': features,
        'isPopular': isPopular,
      };
}

/// A user's subscription to a plan.
///
/// `status` is the only entitlement signal. The backend creates user
/// subscriptions as `Pending`; only an administrator can move one to `Active`.
class Subscription {
  final String id;
  final String userId;
  final String planId;
  final String planTitle;
  final String status;

  const Subscription({
    required this.id,
    this.userId = '',
    this.planId = '',
    this.planTitle = '',
    this.status = 'Pending',
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      planId: json['planId']?.toString() ?? '',
      planTitle: json['planTitle']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Pending',
    );
  }

  /// What to show as the record's name. Never treated as proof of a paid plan.
  String get displayTitle =>
      planTitle.isNotEmpty ? planTitle : (planId.isNotEmpty ? planId : 'Subscription');
}

class NotificationItem {
  final String id;
  final String userId;
  final String title;
  final String content;
  final String type;
  final bool read;

  NotificationItem({
    required this.id,
    this.userId = '',
    required this.title,
    this.content = '',
    this.type = '',
    this.read = false,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      read: json['read'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'type': type,
        if (userId.isNotEmpty) 'userId': userId,
      };
}

/// Dashboard statistics returned by GET /api/dashboard/stats
class DashboardStats {
  final int users;
  final int lawyers;
  final int cases;
  final int bookings;
  final int reviews;
  final int plans;
  final int subscriptions;
  final int activeBookings;
  final int completedBookings;
  final int cancelledBookings;
  final double totalWalletBalance;

  DashboardStats({
    this.users = 0,
    this.lawyers = 0,
    this.cases = 0,
    this.bookings = 0,
    this.reviews = 0,
    this.plans = 0,
    this.subscriptions = 0,
    this.activeBookings = 0,
    this.completedBookings = 0,
    this.cancelledBookings = 0,
    this.totalWalletBalance = 0,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final byStatus = json['bookingsByStatus'] as Map<String, dynamic>? ?? {};
    return DashboardStats(
      users: (json['users'] ?? 0) is int ? json['users'] : 0,
      lawyers: (json['lawyers'] ?? 0) is int ? json['lawyers'] : 0,
      cases: (json['cases'] ?? 0) is int ? json['cases'] : 0,
      bookings: (json['bookings'] ?? 0) is int ? json['bookings'] : 0,
      reviews: (json['reviews'] ?? 0) is int ? json['reviews'] : 0,
      plans: (json['plans'] ?? 0) is int ? json['plans'] : 0,
      subscriptions: (json['subscriptions'] ?? 0) is int ? json['subscriptions'] : 0,
      activeBookings: (byStatus['active'] ?? 0) is int ? byStatus['active'] : 0,
      completedBookings: (byStatus['completed'] ?? 0) is int ? byStatus['completed'] : 0,
      cancelledBookings: (byStatus['cancelled'] ?? 0) is int ? byStatus['cancelled'] : 0,
      totalWalletBalance: (json['totalWalletBalance'] ?? 0).toDouble(),
    );
  }
}

/// Generic paginated response wrapper.
class Paginated<T> {
  final List<T> items;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  Paginated({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });
}
