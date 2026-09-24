import 'package:attendance_app/core/constants/app_constants.dart';

/// A user of the attendance system.
class User {
  const User({
    required this.id,
    required this.username,
    required this.displayName,
    required this.email,
    required this.role,
  });

  final int id;
  final String username;
  final String displayName;
  final String email;
  final UserRole role;

  /// Creates a [User] from a database row map.
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as int,
      username: map['username'] as String,
      displayName: map['display_name'] as String,
      email: map['email'] as String,
      role: UserRole.fromString(map['role'] as String),
    );
  }

  /// Converts this user to a database row map (excludes password).
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'email': email,
      'role': role.value,
    };
  }
}
