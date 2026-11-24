import 'package:flutter/material.dart';
import 'server_api_service.dart';
import 'user_service.dart';

/// Single source of truth for the user's login/session state.
///
/// Holds the logged-in flag + current profile and notifies listeners whenever
/// the state changes so every view can react (show/hide login gates, comment
/// button, profile, etc.).
class AuthService extends ChangeNotifier {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  bool _isLoggedIn = false;
  bool _isGuest = false;
  UserProfile? _currentUser;

  bool get isLoggedIn => _isLoggedIn;
  /// True only for real authenticated users (email/password). Guests are never authenticated.
  bool get isAuthenticated => _isLoggedIn && !_isGuest;
  bool get isGuest => _isGuest;
  UserProfile? get currentUser => _currentUser;

  /// Restore the session from persisted token/user on app start.
  /// Guests never call authentication APIs (check_auth, etc.).
  Future<void> init() async {
    // 1. Instantly restore saved session from local storage so UI never flickers disconnected
    if (!_isGuest) {
      final savedUser = await ServerApiService.getSavedUser();
      final token = await ServerApiService.getToken();
      if (token != null && token.isNotEmpty) {
        _isLoggedIn = true;
        if (savedUser != null) {
          _currentUser = UserProfile.fromSnapshot(savedUser);
        }
        notifyListeners();
      }

      // 2. Validate session and sync latest profile with server
      final loggedIn = await ServerApiService.isLoggedIn();
      _isLoggedIn = loggedIn;
      if (loggedIn) {
        final freshUser = await UserService.getCurrentUser();
        if (freshUser != null) {
          _currentUser = freshUser;
        }
      } else if (token == null || token.isEmpty) {
        _currentUser = null;
      }
    }
    notifyListeners();
  }

  /// Log in with email/password. Persists token + user and notifies listeners.
  Future<Map<String, dynamic>> login(String email, String password) async {
    final result = await ServerApiService.login(email, password);
    if (result['success'] == true) {
      final token = result['token'] as String?;
      if (token != null && token.isNotEmpty) {
        _isGuest = false;
        _isLoggedIn = true;
        final user = result['user'];
        _currentUser = user is Map<String, dynamic>
            ? UserProfile.fromSnapshot(Map<String, dynamic>.from(user))
            : null;
        notifyListeners();
      } else {
        return {'success': false, 'error': 'No auth token received from server'};
      }
    }
    return result;
  }

  /// Sign up a new account. Persists token + user and notifies listeners.
  Future<Map<String, dynamic>> signup(Map<String, dynamic> userData) async {
    final result = await ServerApiService.signup(userData);
    if (result['success'] == true) {
      final token = result['token'] as String?;
      if (token != null && token.isNotEmpty) {
        _isGuest = false;
        _isLoggedIn = true;
        final user = result['user'];
        _currentUser = user is Map<String, dynamic>
            ? UserProfile.fromSnapshot(Map<String, dynamic>.from(user))
            : null;
        notifyListeners();
      } else {
        return {'success': false, 'error': 'No auth token received from server'};
      }
    }
    return result;
  }

  /// Log in as an anonymous/guest user locally. Never calls authentication
  /// APIs and never persists a token — guests must not be able to call
  /// auth endpoints (check_auth, likes, saves, comments, etc.).
  Future<Map<String, dynamic>> loginAnonymously() async {
    _isGuest = true;
    _isLoggedIn = false;
    _currentUser = UserProfile.anonymous();
    notifyListeners();
    return {'success': true};
  }

  /// Log out: clear token/user on server + locally and notify listeners.
  Future<void> logout() async {
    try {
      await ServerApiService.logout();
    } catch (_) {}
    _isGuest = false;
    _isLoggedIn = false;
    _currentUser = null;
    notifyListeners();
  }

  /// Refresh the current user profile from the server.
  Future<void> refreshUser() async {
    if (!_isLoggedIn) return;
    _currentUser = await UserService.getCurrentUser();
    notifyListeners();
  }
}
