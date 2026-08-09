import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

/// User roles in the system.
enum UserRole { admin, reader }

/// A lightweight user profile combining Auth + Firestore role data.
class AppUser {
  final String uid;
  final String email;
  final UserRole role;
  final String displayName;
  final DateTime createdAt;
  final String idToken;
  final String refreshToken;

  const AppUser({
    required this.uid,
    required this.email,
    required this.role,
    required this.displayName,
    required this.createdAt,
    this.idToken = '',
    this.refreshToken = '',
  });

  bool get isAdmin => role == UserRole.admin;
  bool get isReadOnly => role == UserRole.reader;

  factory AppUser.fromFirestore(DocumentSnapshot doc, String email,
      {String idToken = '', String refreshToken = ''}) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AppUser(
      uid: doc.id,
      email: email,
      role: data['role'] == 'admin' ? UserRole.admin : UserRole.reader,
      displayName: data['displayName'] as String? ?? email.split('@').first,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      idToken: idToken,
      refreshToken: refreshToken,
    );
  }
}

/// Firebase Auth REST API URLs
const _signUpUrl =
    'https://identitytoolkit.googleapis.com/v1/accounts:signUp';
const _signInUrl =
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';
const _apiKey = 'AIzaSyCB0-qH9kRP2NhMYnWmJ3LeltDNEIXJo6k';

/// Handles authentication via Firebase Auth REST API (bypasses flutter web SDK issues).
class AuthService {
  final FirebaseFirestore _db;
  final http.Client _client;

  AuthService({FirebaseFirestore? db, http.Client? client})
      : _db = db ?? FirebaseFirestore.instance,
        _client = client ?? http.Client();

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  // ── Register ─────────────────────────────────────────────────────────────

  /// Create a new user via Firebase Auth REST API.
  Future<AppUser> register(String email, String password, String displayName) async {
    final response = await _client.post(
      Uri.parse('$_signUpUrl?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'returnSecureToken': true,
      }),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final errorMsg = data['error']?['message'] ?? 'Registration failed';
      throw AuthException(_mapFirebaseError(errorMsg));
    }

    final uid = data['localId'] as String;
    final idToken = data['idToken'] as String;
    final refreshToken = data['refreshToken'] as String;

    // Determine role: first user gets admin, rest get reader
    final usersSnap = await _users.limit(1).get();
    final role = usersSnap.docs.isEmpty ? UserRole.admin : UserRole.reader;

    // Create profile in Firestore
    await _users.doc(uid).set({
      'email': email.trim(),
      'displayName': displayName.trim(),
      'role': role.name,
      'createdAt': Timestamp.fromDate(DateTime.now()),
    });

    debugPrint('[AuthService] Registered user $uid with role ${role.name}');

    return AppUser(
      uid: uid,
      email: email.trim(),
      role: role,
      displayName: displayName.trim(),
      createdAt: DateTime.now(),
      idToken: idToken,
      refreshToken: refreshToken,
    );
  }

  // ── Login ────────────────────────────────────────────────────────────────

  /// Sign in via Firebase Auth REST API.
  Future<AppUser> signIn(String email, String password) async {
    final response = await _client.post(
      Uri.parse('$_signInUrl?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'returnSecureToken': true,
      }),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final errorMsg = data['error']?['message'] ?? 'Login failed';
      throw AuthException(_mapFirebaseError(errorMsg));
    }

    final uid = data['localId'] as String;
    final idToken = data['idToken'] as String;
    final refreshToken = data['refreshToken'] as String;

    // Get or create profile
    final profile = await _getOrCreateProfile(
      uid,
      email.trim(),
      idToken: idToken,
      refreshToken: refreshToken,
    );

    debugPrint('[AuthService] Signed in user $uid');
    return profile;
  }

  // ── Profile ──────────────────────────────────────────────────────────────

  Future<AppUser> _getOrCreateProfile(String uid, String email,
      {String idToken = '', String refreshToken = ''}) async {
    final doc = await _users.doc(uid).get();

    if (doc.exists) {
      return AppUser.fromFirestore(doc, email,
          idToken: idToken, refreshToken: refreshToken);
    }

    // Profile doesn't exist — create it
    final usersSnap = await _users.limit(1).get();
    final role = usersSnap.docs.isEmpty ? UserRole.admin : UserRole.reader;

    await _users.doc(uid).set({
      'email': email,
      'displayName': email.split('@').first,
      'role': role.name,
      'createdAt': Timestamp.fromDate(DateTime.now()),
    });

    return AppUser(
      uid: uid,
      email: email,
      role: role,
      displayName: email.split('@').first,
      createdAt: DateTime.now(),
      idToken: idToken,
      refreshToken: refreshToken,
    );
  }

  /// Admin updates a user's role.
  Future<void> updateUserRole(String uid, UserRole newRole) async {
    await _users.doc(uid).update({'role': newRole.name});
  }

  /// Admin creates a new user via Firebase Auth REST API.
  /// The user is created with 'reader' role by default.
  Future<void> createUser(String email, String password, String displayName) async {
    final response = await _client.post(
      Uri.parse('$_signUpUrl?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'returnSecureToken': true,
      }),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final errorMsg = data['error']?['message'] ?? 'User creation failed';
      throw AuthException(_mapFirebaseError(errorMsg));
    }

    final uid = data['localId'] as String;

    // Create profile in Firestore with reader role
    await _users.doc(uid).set({
      'email': email.trim(),
      'displayName': displayName.trim(),
      'role': UserRole.reader.name,
      'createdAt': Timestamp.fromDate(DateTime.now()),
    });

    debugPrint('[AuthService] Admin created user $uid (reader)');
  }

  // ── Error mapping ────────────────────────────────────────────────────────

  String _mapFirebaseError(String code) {
    switch (code) {
      case 'EMAIL_NOT_FOUND':
        return 'No account found with this email.';
      case 'INVALID_PASSWORD':
        return 'Incorrect password.';
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Invalid email or password.';
      case 'EMAIL_EXISTS':
        return 'An account already exists with this email.';
      case 'WEAK_PASSWORD : Password should be at least 6 characters':
        return 'Password must be at least 6 characters.';
      case 'INVALID_EMAIL':
        return 'Please enter a valid email address.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Too many attempts. Try again later.';
      case 'OPERATION_NOT_ALLOWED':
        return 'Email/password sign-in is not enabled. Enable it in Firebase Console.';
      default:
        if (code.startsWith('WEAK_PASSWORD')) {
          return 'Password must be at least 6 characters.';
        }
        return 'Authentication failed: $code';
    }
  }

  void dispose() => _client.close();
}

/// Custom exception for auth errors.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}
