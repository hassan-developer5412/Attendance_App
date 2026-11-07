import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/user.dart';
import 'package:attendance_app/core/repositories/user_repository.dart';

/// State store managing user accounts, staff allocations, and suspension states.
class UserStore extends ChangeNotifier {
  UserStore({UserRepository? userRepository})
      : _userRepository = userRepository ?? UserRepository();

  final UserRepository _userRepository;

  List<User> _users = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<User> get users => List.unmodifiable(_users);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Loads all users from the local database.
  Future<void> loadUsers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _users = await _userRepository.getAll();
    } catch (e) {
      _errorMessage = 'Failed to load users: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Creates a new user account with default password policy and role assignment.
  Future<User?> createUser({
    required String username,
    required String displayName,
    required String password,
    required UserRole role,
    String? email,
    String? rollNo,
    String? employeeId,
    String? departmentId,
    String? classId,
    bool isDefaultPassword = true,
  }) async {
    _errorMessage = null;
    try {
      final user = await _userRepository.createUser(
        username: username,
        displayName: displayName,
        password: password,
        role: role,
        email: email,
        rollNo: rollNo,
        employeeId: employeeId,
        departmentId: departmentId,
        classId: classId,
        isDefaultPassword: isDefaultPassword,
      );
      await loadUsers();
      return user;
    } catch (e) {
      _errorMessage = 'Failed to create user: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Toggles suspension of a user account (Admin only).
  Future<void> toggleSuspension(
    String userId, {
    required bool suspend,
    String? reason,
  }) async {
    _errorMessage = null;
    try {
      await _userRepository.toggleSuspension(
        userId,
        suspend: suspend,
        reason: reason,
      );
      await loadUsers();
    } catch (e) {
      _errorMessage = 'Failed to update suspension status: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Updates a user's role and RBAC assignments (Admin only).
  Future<void> updateUserRole(String userId, UserRole newRole) async {
    _errorMessage = null;
    try {
      await _userRepository.updateUserRole(userId, newRole);
      await loadUsers();
    } catch (e) {
      _errorMessage = 'Failed to update user role: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Assigns a teacher or faculty member to a department and/or class (Admin only).
  Future<void> assignTeacher({
    required String userId,
    String? departmentId,
    String? classId,
  }) async {
    _errorMessage = null;
    try {
      await _userRepository.assignTeacherDetails(
        userId: userId,
        departmentId: departmentId,
        classId: classId,
      );
      await loadUsers();
    } catch (e) {
      _errorMessage = 'Failed to assign teacher: $e';
      notifyListeners();
      rethrow;
    }
  }
}
