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
  UserProfile? _currentUser;

  bool get isLoggedIn => _isLoggedIn;
  UserProfile? get currentUser => _currentUser;

  /// Restore the session from persisted token/user on app start.
  Future<void> init() async {
    // 1. Instantly restore saved session from local storage so UI never flickers disconnected
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
    notifyListeners();
  }

  /// Log in with email/password. Persists token + user and notifies listeners.
  Future<Map<String, dynamic>> login(String email, String password) async {
    final result = await ServerApiService.login(email, password);
    if (result['success'] == true) {
      final token = result['token'] as String?;
      if (token != null && token.isNotEmpty) {
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

  /// Log out: clear token/user on server + locally and notify listeners.
  Future<void> logout() async {
    try {
      await ServerApiService.logout();
    } catch (_) {}
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
