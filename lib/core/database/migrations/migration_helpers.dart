import 'package:sqflite/sqflite.dart';


import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Helper methods for database schema changes.
class MigrationHelpers {
  MigrationHelpers._();

  /// Adds a column to [table] if it does not already exist.
  /// Accepts any [DatabaseExecutor] (e.g. [Database] or [Transaction]).
  static Future<void> addColumnIfNotExists(
    DatabaseExecutor db,
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
    DatabaseExecutor db,
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

  // ---------------------------------------------------------------------------
  // RBAC catalogue seeding (permissions, roles, default grants)
  // ---------------------------------------------------------------------------

  /// Canonical permission seed data: (code, module, description).
  static const _kPermissions = <Map<String, String>>[
    {'code': 'student.view', 'module': 'students', 'description': 'View student records'},
    {'code': 'student.create', 'module': 'students', 'description': 'Create new students'},
    {'code': 'student.edit', 'module': 'students', 'description': 'Edit student records'},
    {'code': 'student.delete', 'module': 'students', 'description': 'Delete students'},
    {'code': 'teacher.view', 'module': 'teachers', 'description': 'View teacher records'},
    {'code': 'teacher.create', 'module': 'teachers', 'description': 'Create teachers'},
    {'code': 'teacher.edit', 'module': 'teachers', 'description': 'Edit teachers'},
    {'code': 'teacher.delete', 'module': 'teachers', 'description': 'Delete teachers'},
    {'code': 'attendance.view', 'module': 'attendance', 'description': 'View attendance'},
    {'code': 'attendance.mark', 'module': 'attendance', 'description': 'Mark attendance'},
    {'code': 'attendance.edit', 'module': 'attendance', 'description': 'Edit attendance'},
    {'code': 'attendance.delete', 'module': 'attendance', 'description': 'Delete attendance'},
    {'code': 'attendance.correct_after_deadline', 'module': 'attendance', 'description': 'Correct attendance after deadline'},
    {'code': 'leave.view', 'module': 'leave', 'description': 'View leave requests'},
    {'code': 'leave.approve', 'module': 'leave', 'description': 'Approve or reject leave'},
    {'code': 'user.view', 'module': 'users', 'description': 'View users'},
    {'code': 'user.create', 'module': 'users', 'description': 'Create users'},
    {'code': 'user.edit', 'module': 'users', 'description': 'Edit users'},
    {'code': 'user.delete', 'module': 'users', 'description': 'Delete users'},
    {'code': 'user.manage_roles', 'module': 'users', 'description': 'Manage user roles (Admin / Principal / VP)'},
    {'code': 'class.manage', 'module': 'classes', 'description': 'Manage classes'},
    {'code': 'report.view', 'module': 'reports', 'description': 'View reports'},
    {'code': 'fee.view', 'module': 'fees', 'description': 'View fees'},
    {'code': 'fee.manage', 'module': 'fees', 'description': 'Manage fees'},
    {'code': 'lab.view', 'module': 'lab', 'description': 'View lab inventory'},
    {'code': 'lab.manage', 'module': 'lab', 'description': 'Manage lab inventory'},
    {'code': 'setting.manage', 'module': 'settings', 'description': 'Manage settings'},
    {'code': 'dashboard.view', 'module': 'dashboard', 'description': 'View dashboard'},
  ];

  /// Canonical role seed data: (name, code, description, isInstituteWide).
  static const _kRoles = <Map<String, dynamic>>[
    {'name': 'Administrator', 'code': 'admin', 'description': 'Full system access including user and role management.', 'isInstituteWide': true},
    {'name': 'Principal', 'code': 'principal', 'description': 'Institute-wide academic authority.', 'isInstituteWide': true},
    {'name': 'Vice Principal', 'code': 'vice_principal', 'description': 'Institute-wide academic authority.', 'isInstituteWide': true},
    {'name': 'Head of Department', 'code': 'hod', 'description': 'Department-scoped academic authority (default grant scope).', 'isInstituteWide': false},
    {'name': 'Teacher', 'code': 'teacher', 'description': 'Classroom instruction and attendance for own classes.', 'isInstituteWide': false},
    {'name': 'Student', 'code': 'student', 'description': 'Own records only.', 'isInstituteWide': false},
    {'name': 'Parent', 'code': 'parent', 'description': "Child's records only.", 'isInstituteWide': false},
    {'name': 'Accountant', 'code': 'accountant', 'description': 'Fees and payments.', 'isInstituteWide': false},
    {'name': 'Lab In-Charge', 'code': 'lab_in_charge', 'description': 'Lab inventory.', 'isInstituteWide': false},
    {'name': 'Assistant', 'code': 'assistant', 'description': 'Limited administrative support.', 'isInstituteWide': false},
  ];

  /// Default role → permission grants: (roleCode, permissionCode).
  static final _kRoleGrants = <Map<String, String>>[
    // Institute-wide roles receive every permission.
    for (final roleCode in <String>['admin', 'principal', 'vice_principal'])
      for (final perm in _kPermissions)
        {'roleCode': roleCode, 'permCode': perm['code']!},
    // HOD — department-scoped.
    {'roleCode': 'hod', 'permCode': 'student.view'},
    {'roleCode': 'hod', 'permCode': 'student.edit'},
    {'roleCode': 'hod', 'permCode': 'teacher.view'},
    {'roleCode': 'hod', 'permCode': 'attendance.view'},
    {'roleCode': 'hod', 'permCode': 'attendance.mark'},
    {'roleCode': 'hod', 'permCode': 'attendance.edit'},
    {'roleCode': 'hod', 'permCode': 'leave.view'},
    {'roleCode': 'hod', 'permCode': 'leave.approve'},
    {'roleCode': 'hod', 'permCode': 'report.view'},
    {'roleCode': 'hod', 'permCode': 'class.manage'},
    // Teacher.
    {'roleCode': 'teacher', 'permCode': 'attendance.view'},
    {'roleCode': 'teacher', 'permCode': 'attendance.mark'},
    {'roleCode': 'teacher', 'permCode': 'student.view'},
    {'roleCode': 'teacher', 'permCode': 'leave.view'},
    // Student / Parent — own records.
    {'roleCode': 'student', 'permCode': 'attendance.view'},
    {'roleCode': 'student', 'permCode': 'leave.view'},
    {'roleCode': 'student', 'permCode': 'dashboard.view'},
    {'roleCode': 'parent', 'permCode': 'attendance.view'},
    {'roleCode': 'parent', 'permCode': 'leave.view'},
    {'roleCode': 'parent', 'permCode': 'dashboard.view'},
    // Accountant.
    {'roleCode': 'accountant', 'permCode': 'fee.view'},
    {'roleCode': 'accountant', 'permCode': 'fee.manage'},
    {'roleCode': 'accountant', 'permCode': 'report.view'},
    // Lab In-Charge.
    {'roleCode': 'lab_in_charge', 'permCode': 'lab.view'},
    {'roleCode': 'lab_in_charge', 'permCode': 'lab.manage'},
    // Assistant.
    {'roleCode': 'assistant', 'permCode': 'student.view'},
    {'roleCode': 'assistant', 'permCode': 'attendance.view'},
    {'roleCode': 'assistant', 'permCode': 'dashboard.view'},
  ];

  /// Idempotently seeds the predefined permissions, roles and default grants.
  ///
  /// Safe to run on fresh installs (`_onCreate`) and on upgrades
  /// (`SchemaMigrationV9`); existing rows are never overwritten.
  static Future<void> seedRolesAndPermissions(DatabaseExecutor db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final batch = db.batch();

    for (final p in _kPermissions) {
      final existing = await db.query(
        'permissions',
        where: 'code = ?',
        whereArgs: [p['code']],
        limit: 1,
      );
      if (existing.isEmpty) {
        batch.insert('permissions', {
          'id': UuidUtils.deterministic('permissions', p['code']!),
          'code': p['code'],
          'module': p['module'],
          'description': p['description'],
          'created_at': now,
          'updated_at': now,
          'sync_status': 'SYNCED',
          'is_deleted': 0,
          'is_synced': 1,
          'institute_id': AppConstants.defaultInstituteId,
        });
      }
    }

    for (final r in _kRoles) {
      final existing = await db.query(
        'roles',
        where: 'code = ?',
        whereArgs: [r['code']],
        limit: 1,
      );
      if (existing.isEmpty) {
        batch.insert('roles', {
          'id': UuidUtils.deterministic('roles', r['code']),
          'name': r['name'],
          'code': r['code'],
          'description': r['description'],
          'is_custom': 0,
          'is_institute_wide': r['isInstituteWide'] ? 1 : 0,
          'created_at': now,
          'updated_at': now,
          'sync_status': 'SYNCED',
          'is_deleted': 0,
          'is_synced': 1,
          'institute_id': AppConstants.defaultInstituteId,
        });
      }
    }

    await batch.commit(noResult: true);

    for (final g in _kRoleGrants) {
      final roleId = UuidUtils.deterministic('roles', g['roleCode']!);
      final existing = await db.query(
        'role_permissions',
        where: 'role_id = ? AND permission_code = ?',
        whereArgs: [roleId, g['permCode']],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert('role_permissions', {
          'role_id': roleId,
          'permission_code': g['permCode'],
          'created_at': now,
        });
      }
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
