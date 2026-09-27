import 'package:sqflite/sqflite.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Helper methods for database schema changes.
class MigrationHelpers {
  MigrationHelpers._();

  /// Adds a column to [table] if it does not already exist.
  static Future<void> addColumnIfNotExists(
    Database db,
    String table,
    String column,
    String typeAndConstraints,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final columnNames = info.map((row) => row['name'] as String).toSet();
    if (!columnNames.contains(column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $typeAndConstraints');
    }
  }

  /// Seeds canonical GILT academic departments idempotently.
  static Future<void> seedDepartments(DatabaseExecutor db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final dept in AcademicDepartment.values) {
      final deptId = UuidUtils.deterministic('departments', dept.code);
      final existing = await db.query(
        'departments',
        where: 'code = ?',
        whereArgs: [dept.code],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert('departments', {
          'id': deptId,
          'name': dept.title,
          'code': dept.code,
          'created_at': now,
          'updated_at': now,
          'sync_status': 'SYNCED',
          'is_deleted': 0,
        });
      }
    }
  }
}
