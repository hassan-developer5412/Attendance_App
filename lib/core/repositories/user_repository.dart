import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/user.dart';
import 'package:attendance_app/core/services/sync_service.dart';

class UserRepository {
  UserRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// Looks a user up by UUID primary key.
  Future<User?> getById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'users',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return User.fromMap(rows.first);
  }

  Future<User?> authenticate(String username, String passwordHash) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'users',
      where: 'username = ? AND password_hash = ? AND is_deleted = 0',
      whereArgs: [username.trim(), passwordHash],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return User.fromMap(rows.first);
  }

  /// Updates the profile of the user identified by UUID.
  Future<void> updateProfile({
    required String id,
    required String displayName,
    required String email,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'users',
      {
        'display_name': displayName.trim(),
        'email': email.trim(),
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    SyncService.instance.schedulePush('users', idColumn: 'id', idValue: id);
  }

  Future<void> softDelete(String id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'users',
      {'is_deleted': 1, 'updated_at': now, 'sync_status': 'PENDING'},
      where: 'id = ?',
      whereArgs: [id],
    );
    SyncService.instance.schedulePush('users', idColumn: 'id', idValue: id);
  }
}
