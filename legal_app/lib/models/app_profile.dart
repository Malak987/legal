/// A Firestore-backed application profile — the document at `users/{uid}`.
///
/// Distinct from the Firebase Authentication account. Auth owns the credential
/// and the uid; this document owns the name, contact details and the `role`
/// the backend authorizes against. The two are joined only by the document id
/// being the Auth uid.
///
/// Parsing is deliberately defensive: the document is written by the backend
/// but also editable in the Firebase console, and older records predate fields
/// such as `address`. A malformed value must never crash a screen.
class AppProfile {
  const AppProfile({
    required this.uid,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.role = 'client',
    this.avatar = '',
    this.address = '',
  });

  /// The Auth uid this profile belongs to (`users/{uid}`).
  final String uid;
  final String name;
  final String email;
  final String phone;

  /// `client`, `lawyer` or `admin`. Server-owned: nothing in the app may set it.
  final String role;
  final String avatar;
  final String address;

  /// True only for the exact `admin` role. An unknown or mis-cased role is
  /// treated as "not an administrator", matching the backend, which compares
  /// `role === 'admin'` strictly.
  bool get isAdmin => role == 'admin';
  bool get isLawyer => role == 'lawyer';
  bool get isClient => role == 'client';

  /// Name to show in the UI, falling back to the email local-part.
  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    final at = email.indexOf('@');
    if (at > 0) return email.substring(0, at);
    return email;
  }

  /// Builds a profile from a `users/{uid}` document.
  ///
  /// `GET /api/users/:id` returns `{ id, ...documentData }`, so the id may
  /// arrive as `id`; documents written elsewhere may only carry `uid`. Both
  /// are accepted, and a missing role falls back to `client` — the same
  /// default the backend applies when it reads a profile.
  factory AppProfile.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      if (value == null) return '';
      return value.toString().trim();
    }

    final id = text('id');
    final uid = id.isNotEmpty ? id : text('uid');
    final role = text('role');

    return AppProfile(
      uid: uid,
      name: text('name'),
      email: text('email'),
      phone: text('phone'),
      role: role.isEmpty ? 'client' : role,
      avatar: text('avatar'),
      address: text('address'),
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        'email': email,
        'phone': phone,
        'role': role,
        'avatar': avatar,
        'address': address,
      };

  @override
  String toString() => 'AppProfile($uid, role: $role)';
}
