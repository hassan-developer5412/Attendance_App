import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/migrations/migration_helpers.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Additive v7 migration — user session security, suspension flags, and
/// identity linking.
///
/// All changes are additive: no table is dropped and no existing row is
/// modified or deleted, so `users`, `teachers`, `students`, `classes` and
/// `attendance_records` keep every pre-migration row.
///
/// Changes (executed inside a single SQLite transaction):
///   * `users`: add nullable `auth_user_id`, `is_default_password`,
///     `is_suspended`, `suspended_at`, `suspended_reason`,
///     `failed_login_attempts`, `locked_until`, `password_changed_at`,
///     `last_login_at`, `session_expires_at`.
///   * `teachers`: add nullable `user_id TEXT REFERENCES users(id)
///     ON DELETE SET NULL`.
///   * `CREATE UNIQUE INDEX IF NOT EXISTS idx_users_auth_user_id
///     ON users(auth_user_id)`.
///   * `CREATE INDEX IF NOT EXISTS idx_teachers_user_id ON teachers(user_id)`.
///   * Flag any pre-existing admin account whose password hash matches the
///     default credential as `is_default_password = 1`. The admin id and the
///     SHA-256 hash are computed in Dart first, then applied via parameter
///     binding — no inline Dart expressions appear in raw SQL.
class SchemaMigrationV7 {
  SchemaMigrationV7._();

  static Future<void> execute(Database db) async {
    await db.transaction((txn) async {
      // ------------------------------------------------------------------
      // 1. Extend `users` with session-security columns (additive only).
      // ------------------------------------------------------------------
      await MigrationHelpers.addColumnIfNotExists(
        txn,
        'users',
        'auth_user_id',
        'TEXT',
      );
      await MigrationHelpers.addColumnIfNotExists(
        txn,
        'users',
        'is_default_password',
        'INTEGER DEFAULT 0',
      );
      await MigrationHelpers.addColumnIfNotExists(
        txn,
        'users',
        'is_suspended',
        'INTEGER DEFAULT 0',
      );
      await MigrationHelpers.addColumnIfNotExists(
        txn,
        'users',
        'suspended_at',
        'TEXT',
      );
      await MigrationHelpers.addColumnIfNotExists(
        txn,
        'users',
        'suspended_reason',
        'TEXT',
      );
      await MigrationHelpers.addColumnIfNotExists(
        txn,
        'users',
        'failed_login_attempts',
        'INTEGER DEFAULT 0',
      );
      await MigrationHelpers.addColumnIfNotExists(
        txn,
        'users',
        'locked_until',
        'TEXT',
      );
      await MigrationHelpers.addColumnIfNotExists(
        txn,
        'users',
        'password_changed_at',
        'TEXT',
      );
      await MigrationHelpers.addColumnIfNotExists(
        txn,
        'users',
        'last_login_at',
        'TEXT',
      );
      await MigrationHelpers.addColumnIfNotExists(
        txn,
        'users',
        'session_expires_at',
        'TEXT',
      );

      // ------------------------------------------------------------------
      // 2. Link teachers to their owning user account.
      // ------------------------------------------------------------------
      await MigrationHelpers.addColumnIfNotExists(
        txn,
        'teachers',
        'user_id',
        'TEXT REFERENCES users(id) ON DELETE SET NULL',
      );

      // ------------------------------------------------------------------
      // 3. Flag any pre-existing default-password admin account.
      //    Values are computed in Dart, then bound as parameters.
      // ------------------------------------------------------------------
      final adminId = UuidUtils.deterministic('users', 'admin');
      final defaultHash = sha256
          .convert(utf8.encode(AppConstants.defaultAdminPassword))
          .toString();
      await txn.update(
        'users',
        {'is_default_password': 1},
        where: 'id = ? AND password_hash = ?',
        whereArgs: [adminId, defaultHash],
      );

      // ------------------------------------------------------------------
      // 4. Supporting indexes (idempotent via IF NOT EXISTS).
      // ------------------------------------------------------------------
      await txn.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_users_auth_user_id
        ON users(auth_user_id)
      ''');
      await txn.execute('''
        CREATE INDEX IF NOT EXISTS idx_teachers_user_id
        ON teachers(user_id)
      ''');
    });
  }
}
