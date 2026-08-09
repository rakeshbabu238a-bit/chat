import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth_service.dart';

const _sessionKey = 'auth_session';

/// Authentication state manager with localStorage persistence.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final SharedPreferences _prefs;

  AuthProvider(this._authService, this._prefs) {
    _restoreSession();
  }

  // ── State ────────────────────────────────────────────────────────────────

  AppUser? _appUser;
  bool _isLoading = true;
  String? _error;

  AppUser? get appUser => _appUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _appUser != null;
  bool get isAdmin => _appUser?.isAdmin ?? false;
  bool get isReadOnly => _appUser?.isReadOnly ?? false;
  String? get error => _error;

  // ── Persistence ──────────────────────────────────────────────────────────

  void _restoreSession() {
    try {
      final raw = _prefs.getString(_sessionKey);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _appUser = AppUser(
          uid: data['uid'] as String,
          email: data['email'] as String,
          role: data['role'] == 'admin' ? UserRole.admin : UserRole.reader,
          displayName: data['displayName'] as String,
          createdAt: DateTime.parse(data['createdAt'] as String),
          idToken: data['idToken'] as String? ?? '',
          refreshToken: data['refreshToken'] as String? ?? '',
        );
        debugPrint('[Auth] Session restored for ${_appUser!.email}');
      }
    } catch (e) {
      debugPrint('[Auth] Restore error: $e');
    }
    _isLoading = false;
  }

  void _saveSession(AppUser user) {
    final json = jsonEncode({
      'uid': user.uid,
      'email': user.email,
      'role': user.role.name,
      'displayName': user.displayName,
      'createdAt': user.createdAt.toIso8601String(),
      'idToken': user.idToken,
      'refreshToken': user.refreshToken,
    });
    _prefs.setString(_sessionKey, json);
  }

  void _clearSession() {
    _prefs.remove(_sessionKey);
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _appUser = await _authService.signIn(email, password);
      _saveSession(_appUser!);
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    _appUser = null;
    _clearSession();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ── Admin: User management ───────────────────────────────────────────────

  /// Create a new user (admin only). Uses Firebase Auth REST API + Firestore.
  Future<void> createUser(String email, String password, String displayName) async {
    await _authService.createUser(email, password, displayName);
  }

  /// Get all users from Firestore (admin only).
  Future<List<Map<String, dynamic>>> listUsers() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'uid': doc.id,
        'email': data['email'] ?? '',
        'displayName': data['displayName'] ?? '',
        'role': data['role'] ?? 'reader',
        'createdAt': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
      };
    }).toList();
  }

  /// Delete a user from Firestore (admin only).
  /// Note: This removes their profile; Firebase Auth account remains but they can't access the app.
  Future<void> deleteUser(String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).delete();
  }

  /// Update a user's role (admin only).
  Future<void> updateUserRole(String uid, UserRole newRole) async {
    await _authService.updateUserRole(uid, newRole);
  }

  @override
  void dispose() {
    _authService.dispose();
    super.dispose();
  }
}
