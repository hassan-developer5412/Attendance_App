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
    final info = await db.rawQuery('PRAGMA table_info(departments)');
    final columnNames = info.map((row) => row['name'] as String).toSet();
    final hasDescription = columnNames.contains('description');
    final hasIsActive = columnNames.contains('is_active');

    for (final dept in AcademicDepartment.values) {
      final deptId = UuidUtils.deterministic('departments', dept.code);
      final existing = await db.query(
        'departments',
        where: 'code = ?',
        whereArgs: [dept.code],
        limit: 1,
      );
      if (existing.isEmpty) {
        final row = <String, dynamic>{
          'id': deptId,
          'name': dept.title,
          'code': dept.code,
          'created_at': now,
          'updated_at': now,
          'sync_status': 'SYNCED',
          'is_deleted': 0,
        };
        if (hasDescription) row['description'] = '';
        if (hasIsActive) row['is_active'] = 1;
        await db.insert('departments', row);
      }
    }
  }

  /// Drops [column] from [table] when the SQLite engine supports it.
  ///
  /// SQLite only gained `ALTER TABLE ... DROP COLUMN` in 3.35. If the engine in
  /// use is older the call throws and the (unused) column is simply left in
  /// place — existing data is never lost either way.
  static Future<void> dropColumnIfExists(
    Database db,
    String table,
    String column,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final hasColumn = info.any((row) => row['name'] == column);
    if (!hasColumn) return;
    try {
      await db.execute('ALTER TABLE $table DROP COLUMN $column');
    } catch (_) {
      // Engine cannot drop columns; leave the legacy column untouched.
    }
  }

  /// Seeds the canonical GILT academic sessions idempotently.
  ///
  /// This only runs when the table is empty, so it never overwrites sessions a
  /// user has created or marked as current. Previous sessions are retained so
  /// historic records remain available.
  static Future<void> seedAcademicSessions(DatabaseExecutor db) async {
    final existing = await db.query('academic_sessions', limit: 1);
    if (existing.isNotEmpty) return;

    final now = DateTime.now().toUtc().toIso8601String();
    final names = <String>['2025-26', '2026-27', '2027-28'];
    final currentName = currentAcademicSessionName(DateTime.now());

    for (final name in names) {
      final startYear = int.parse(name.split('-').first);
      await db.insert('academic_sessions', {
        'id': UuidUtils.deterministic('academic_sessions', name),
        'name': name,
        'start_date': DateTime.utc(startYear, 8, 1).toIso8601String(),
        'end_date': DateTime.utc(startYear + 1, 6, 30).toIso8601String(),
        'is_current': name == currentName ? 1 : 0,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'SYNCED',
        'is_deleted': 0,
      });
    }
  }

  /// Returns the academic session label (e.g. `2026-27`) for [date].
  ///
  /// An academic session starts in August, so months August–December map to
  /// `<year>-<year+1>` and January–July map to `<year-1>-<year>`.
  static String currentAcademicSessionName(DateTime date) {
    final startYear = date.month >= 8 ? date.year : date.year - 1;
    final endYear = startYear + 1;
    final endLabel = (endYear % 100).toString().padLeft(2, '0');
    return '$startYear-$endLabel';
  }
}
