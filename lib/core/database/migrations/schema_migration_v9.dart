import 'package:sqflite/sqflite.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/migrations/migration_helpers.dart';

/// v9 — Role-Based Access Control (RBAC) catalogue.
///
/// Adds the `roles`, `permissions`, `role_permissions`, `user_roles` and
/// `user_departments` tables used by [PermissionService], and seeds the
/// predefined roles (Principal, Vice Principal, Admin, HOD, Teacher, Student,
/// Parent, Accountant, Lab In-Charge, Assistant) with their default grants.
///
/// All changes are additive (`CREATE TABLE IF NOT EXISTS`) and the seed is
/// idempotent, so the migration is safe to re-run.
class SchemaMigrationV9 {
  SchemaMigrationV9._();

  static Future<void> execute(Database db) async {
    // -------------------------------------------------------------------------
    // 1. Detect and safely clean up legacy placeholder tables from early drafts.
    // If 'roles' exists without the 'code' column, it was created with an old
    // INTEGER AUTOINCREMENT schema and contains no RBAC production data.
    // -------------------------------------------------------------------------
    final rolesInfo = await db.rawQuery("PRAGMA table_info('roles')");
    final rolesColumns = rolesInfo.map((row) => row['name'] as String).toSet();
    if (rolesInfo.isNotEmpty && !rolesColumns.contains('code')) {
      await db.execute('DROP TABLE IF EXISTS role_permissions');
      await db.execute('DROP TABLE IF EXISTS user_roles');
      await db.execute('DROP TABLE IF EXISTS user_departments');
      await db.execute('DROP TABLE IF EXISTS permissions');
      await db.execute('DROP TABLE IF EXISTS roles');
    } else {
      // Check for legacy column structure in auxiliary junction tables
      final rpInfo = await db.rawQuery("PRAGMA table_info('role_permissions')");
      final rpColumns = rpInfo.map((row) => row['name'] as String).toSet();
      if (rpInfo.isNotEmpty && !rpColumns.contains('permission_code')) {
        await db.execute('DROP TABLE IF EXISTS role_permissions');
      }

      final urInfo = await db.rawQuery("PRAGMA table_info('user_roles')");
      final urColumns = urInfo.map((row) => row['name'] as String).toSet();
      if (urInfo.isNotEmpty && !urColumns.contains('id')) {
        await db.execute('DROP TABLE IF EXISTS user_roles');
      }
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS roles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT NOT NULL UNIQUE,
        description TEXT NOT NULL DEFAULT '',
        is_custom INTEGER NOT NULL DEFAULT 0,
        is_institute_wide INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'SYNCED',
        is_deleted INTEGER NOT NULL DEFAULT 0,
        is_synced INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS permissions (
        id TEXT PRIMARY KEY,
        code TEXT NOT NULL UNIQUE,
        module TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'SYNCED',
        is_deleted INTEGER NOT NULL DEFAULT 0,
        is_synced INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS role_permissions (
        role_id TEXT NOT NULL,
        permission_code TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (role_id, permission_code)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_roles (
        id TEXT,
        user_id TEXT NOT NULL,
        role_id TEXT NOT NULL,
        institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
        assigned_at TEXT,
        assigned_by TEXT,
        updated_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'PENDING',
        is_deleted INTEGER NOT NULL DEFAULT 0,
        is_synced INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (user_id, role_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_departments (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        department_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'PENDING',
        is_deleted INTEGER NOT NULL DEFAULT 0,
        UNIQUE(user_id, department_id)
      )
    ''');

    await MigrationHelpers.seedRolesAndPermissions(db);

    // Supporting indexes.
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_role_permissions_role_id
      ON role_permissions(role_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_user_roles_user_id
      ON user_roles(user_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_user_roles_role_id
      ON user_roles(role_id)
    ''');
  }
}
