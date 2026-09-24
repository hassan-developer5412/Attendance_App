import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/user.dart';

/// Manages user authentication state backed by the SQLite users table.
class AuthStore extends ChangeNotifier {
  User? _currentUser;

  /// The currently logged-in user, or `null` if unauthenticated.
  User? get currentUser => _currentUser;

  /// Whether a user is currently logged in.
  bool get isLoggedIn => _currentUser != null;

  /// Restores the session from [SharedPreferences] if a user was previously
  /// logged in.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final userIdStr = prefs.getString(AppConstants.prefUserId);
    if (userIdStr == null) return;

    final userId = int.tryParse(userIdStr);
    if (userId == null) return;

    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      _currentUser = User.fromMap(rows.first);
      notifyListeners();
    }
  }

  /// Attempts to authenticate with [username] and [password].
  ///
  /// Returns the authenticated [User] on success, or `null` on failure.
  /// Persists the session to [SharedPreferences].
  Future<User?> login(String username, String password) async {
    final db = await DatabaseHelper.instance.database;
    final hash = sha256.convert(utf8.encode(password)).toString();

    final rows = await db.query(
      'users',
      where: 'username = ? AND password_hash = ?',
      whereArgs: [username.trim(), hash],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    _currentUser = User.fromMap(rows.first);

    // Persist session.
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

  /// Updates the current user's display name and email in the database.
  Future<void> updateProfile({
    required String displayName,
    required String email,
  }) async {
    if (_currentUser == null) return;

    final db = await DatabaseHelper.instance.database;
    await db.update(
      'users',
      {'display_name': displayName.trim(), 'email': email.trim()},
      where: 'id = ?',
      whereArgs: [_currentUser!.id],
    );

    _currentUser = User(
      id: _currentUser!.id,
      username: _currentUser!.username,
      displayName: displayName.trim(),
      email: email.trim(),
      role: _currentUser!.role,
    );
    notifyListeners();
  }
}
