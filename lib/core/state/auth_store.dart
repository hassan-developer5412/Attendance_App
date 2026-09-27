import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/user.dart';
import 'package:attendance_app/core/repositories/user_repository.dart';

/// Manages user authentication state backed by UserRepository.
class AuthStore extends ChangeNotifier {
  AuthStore({UserRepository? userRepository})
      : _userRepository = userRepository ?? UserRepository();

  final UserRepository _userRepository;
  User? _currentUser;

  /// The currently logged-in user, or `null` if unauthenticated.
  User? get currentUser => _currentUser;

  /// Whether a user is currently logged in.
  bool get isLoggedIn => _currentUser != null;

  /// Restores the session from [SharedPreferences] if a user was previously logged in.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final userIdStr = prefs.getString(AppConstants.prefUserId);
    if (userIdStr == null || userIdStr.isEmpty) return;

    final user = await _userRepository.getById(userIdStr);
    if (user != null) {
      _currentUser = user;
      notifyListeners();
    }
  }

  /// Attempts to authenticate with [username] and [password].
  Future<User?> login(String username, String password) async {
    final hash = sha256.convert(utf8.encode(password)).toString();
    final user = await _userRepository.authenticate(username, hash);

    if (user == null) return null;

    _currentUser = user;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConstants.prefUserId,
      _currentUser!.id.toString(),
    );
    await prefs.setString(
      AppConstants.prefUserRole,
      _currentUser!.role.value,
    );

    notifyListeners();
    return _currentUser;
  }

  /// Logs the current user out and clears the saved session.
  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefUserId);
    await prefs.remove(AppConstants.prefUserRole);
    notifyListeners();
  }

  /// Updates the current user's display name and email.
  Future<void> updateProfile({
    required String displayName,
    required String email,
  }) async {
    if (_currentUser == null) return;

    await _userRepository.updateProfile(
      id: _currentUser!.id,
      displayName: displayName.trim(),
      email: email.trim(),
    );

    _currentUser = _currentUser!.copyWith(
      displayName: displayName.trim(),
      email: email.trim(),
    );
    notifyListeners();
  }
}
