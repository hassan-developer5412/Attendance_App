import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/user.dart';
import 'package:attendance_app/core/services/sync_service.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Outcome of [UserRepository.authenticate].
class AuthenticationResult {
  const AuthenticationResult({
    required this.user,
    this.wasLegacyHash = false,
    this.isSuspended = false,
    this.isLocked = false,
  });

  /// The authenticated user (password hash excluded from the model).
  final User user;

  /// True when the password was verified against a legacy SHA-256 hash that
  /// has since been transparently upgraded to bcrypt.
  final bool wasLegacyHash;

  /// True when the row exists but the account is suspended. Login must be
  /// blocked even if the password is correct.
  final bool isSuspended;

  /// True when the account is temporarily locked after repeated failed
  /// attempts.
  final bool isLocked;
}

class UserRepository {
  UserRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// Maximum consecutive failed password attempts before the account is
  /// locked.
  static const int maxFailedLoginAttempts = 5;

  /// How long an account stays locked after reaching
  /// [maxFailedLoginAttempts].
  static const Duration lockoutDuration = Duration(minutes: 15);

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

  /// Authenticates [identifier]/[password] against the local SQLite store.
  ///
  /// [identifier] may be a username, roll number, or employee ID.
  ///
  /// Supports two hash formats:
  ///  * legacy SHA-256 (64 hex characters) — on a successful match the hash
  ///    is transparently upgraded to bcrypt and persisted back to SQLite;
  ///  * bcrypt (`$2a$`/`$2b$`/`$2y$`) — verified directly with [BCrypt.checkpw].
  ///
  /// Returns `null` when the user does not exist, is soft-deleted, or the
  /// password does not match (failed attempts are counted in that case).
  /// Returns a result with [AuthenticationResult.isSuspended] /
  /// [AuthenticationResult.isLocked] set when the account exists but must
  /// not be logged into.
  Future<AuthenticationResult?> authenticate(
      String identifier, String password) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'users',
      where:
          '(username = ? OR roll_no = ? OR employee_id = ?) AND is_deleted = 0',
      whereArgs: [
        identifier.trim(),
        identifier.trim(),
        identifier.trim(),
      ],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final storedHash = row['password_hash'] as String;
    final user = User.fromMap(row);

    // Suspended accounts can never log in — never even check the password,
    // so no information about the password is leaked for suspended rows.
    if (user.isSuspended) {
      return AuthenticationResult(user: user, isSuspended: true);
    }

    // Locked accounts must wait out the lockout window.
    if (user.isLocked) {
      return AuthenticationResult(user: user, isLocked: true);
    }

    final isLegacySha256 = _isLegacySha256Hash(storedHash);
    final valid = isLegacySha256
        ? _sha256(password) == storedHash
        : BCrypt.checkpw(password, storedHash);

    if (!valid) {
      await _recordFailedAttempt(user.id);
      return null;
    }

    // Successful login: clear the failure counter and any lockout.
    await _clearFailedAttempts(user.id);

    // Transparently upgrade legacy SHA-256 hashes to bcrypt on first
    // successful login so existing accounts are migrated without a reset.
    if (isLegacySha256) {
      await _rehashToBcrypt(user.id, password);
    }

    return AuthenticationResult(user: user, wasLegacyHash: isLegacySha256);
  }

  /// Looks a user up by email address (used by the OTP password-recovery
  /// flow). Comparison is case-insensitive.
  Future<User?> getByEmail(String email) async {
    final db = await _dbHelper.database;
    final normalized = email.trim().toLowerCase();
    final rows = await db.query(
      'users',
      where: 'LOWER(email) = ? AND is_deleted = 0',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return User.fromMap(rows.first);
  }

  /// Replaces a legacy SHA-256 hash with a bcrypt hash for [userId] and flags
  /// the row for the next sync push.
  Future<void> _rehashToBcrypt(String userId, String password) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'users',
      {
        'password_hash': BCrypt.hashpw(password, BCrypt.gensalt()),
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    SyncService.instance.schedulePush('users', idColumn: 'id', idValue: userId);
  }

  /// Updates [userId]'s password to a bcrypt hash of [newPassword], clears the
  /// default-password flag, records the change timestamp, and flags the row
  /// for sync.
  Future<void> updatePassword(String userId, String newPassword) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'users',
      {
        'password_hash': BCrypt.hashpw(newPassword, BCrypt.gensalt()),
        'is_default_password': 0,
        'password_changed_at': now,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    SyncService.instance.schedulePush('users', idColumn: 'id', idValue: userId);
  }

  /// Records the session timestamps for [userId] (last login and absolute
  /// session expiry) and flags the row for sync.
  Future<void> updateSessionTimestamps({
    required String userId,
    required DateTime lastLoginAt,
    required DateTime sessionExpiresAt,
  }) async {
    final db = await _dbHelper.database;
    await db.update(
      'users',
      {
        'last_login_at': lastLoginAt.toUtc().toIso8601String(),
        'session_expires_at': sessionExpiresAt.toUtc().toIso8601String(),
        'updated_at': lastLoginAt.toUtc().toIso8601String(),
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    SyncService.instance.schedulePush('users', idColumn: 'id', idValue: userId);
  }

  /// Returns `true` when [hash] looks like a legacy unsalted SHA-256 digest
  /// (exactly 64 hex characters) rather than a bcrypt hash.
  static bool _isLegacySha256Hash(String hash) =>
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash);

  static String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  /// Records a failed password attempt for [userId]: increments
  /// [failed_login_attempts] and, when [maxFailedLoginAttempts] is reached,
  /// sets [locked_until] to now + [lockoutDuration].
  Future<void> _recordFailedAttempt(String userId) async {
    final db = await _dbHelper.database;
    final currentRow = await db.query(
      'users',
      columns: ['failed_login_attempts'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    final current =
        (currentRow.first['failed_login_attempts'] as int? ?? 0) + 1;
    final now = DateTime.now().toUtc().toIso8601String();
    final updates = <String, dynamic>{
      'failed_login_attempts': current,
      'updated_at': now,
      'sync_status': 'PENDING',
    };
    if (current >= maxFailedLoginAttempts) {
      updates['locked_until'] =
          DateTime.now().toUtc().add(lockoutDuration).toIso8601String();
    }
    await db.update(
      'users',
      updates,
      where: 'id = ?',
      whereArgs: [userId],
    );
    SyncService.instance.schedulePush('users', idColumn: 'id', idValue: userId);
  }

  /// Clears failed attempts and any lockout for [userId] after a successful
  /// login, and stamps [last_login_at].
  Future<void> _clearFailedAttempts(String userId) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'users',
      {
        'failed_login_attempts': 0,
        'locked_until': null,
        'last_login_at': now,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    SyncService.instance.schedulePush('users', idColumn: 'id', idValue: userId);
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

  /// Returns all active users in the system, ordered by display name.
  Future<List<User>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'users',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'display_name ASC, username ASC',
    );
    return rows.map(User.fromMap).toList();
  }

  /// Creates a new user account with hashed password and initial role/assignments.
  Future<User> createUser({
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
    final db = await _dbHelper.database;
    final id = UuidUtils.generate();
    final now = DateTime.now().toUtc().toIso8601String();
    final passwordHash = BCrypt.hashpw(password, BCrypt.gensalt());
    final cleanEmail = (email != null && email.trim().isNotEmpty)
        ? email.trim()
        : '${username.trim().toLowerCase()}@institute.edu';

    final userMap = <String, dynamic>{
      'id': id,
      'username': username.trim(),
      'roll_no': rollNo?.trim().isNotEmpty == true ? rollNo!.trim() : null,
      'employee_id':
          employeeId?.trim().isNotEmpty == true ? employeeId!.trim() : null,
      'password_hash': passwordHash,
      'display_name': displayName.trim(),
      'email': cleanEmail,
      'role': role.value,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'PENDING',
      'is_deleted': 0,
      'institute_id': AppConstants.defaultInstituteId,
      'is_synced': 0,
      'is_default_password': isDefaultPassword ? 1 : 0,
      'is_suspended': 0,
      'failed_login_attempts': 0,
    };

    await db.insert('users', userMap);
    SyncService.instance.schedulePush('users', idColumn: 'id', idValue: id);

    // Link user to role in user_roles table if the role exists
    final roleRows = await db.query(
      'roles',
      where: 'code = ? AND is_deleted = 0',
      whereArgs: [role.value],
      limit: 1,
    );
    if (roleRows.isNotEmpty) {
      final roleId = roleRows.first['id'] as String;
      final userRoleId = UuidUtils.generate();
      await db.insert('user_roles', {
        'id': userRoleId,
        'user_id': id,
        'role_id': roleId,
        'institute_id': AppConstants.defaultInstituteId,
        'assigned_at': now,
        'sync_status': 'PENDING',
        'is_deleted': 0,
      });
      SyncService.instance.schedulePush(
        'user_roles',
        idColumn: 'id',
        idValue: userRoleId,
      );
    }

    // Link user to department in user_departments if specified
    if (departmentId != null && departmentId.isNotEmpty) {
      final userDeptId = UuidUtils.generate();
      await db.insert('user_departments', {
        'id': userDeptId,
        'user_id': id,
        'department_id': departmentId,
        'created_at': now,
        'sync_status': 'PENDING',
        'is_deleted': 0,
      });
      SyncService.instance.schedulePush(
        'user_departments',
        idColumn: 'id',
        idValue: userDeptId,
      );
    }

    // If teacher or HOD, link or create teacher profile
    if (role == UserRole.teacher || role == UserRole.hod) {
      final existingTeacher = await db.query(
        'teachers',
        where:
            'username = ? OR (employee_code IS NOT NULL AND employee_code = ?)',
        whereArgs: [username.trim(), employeeId?.trim() ?? ''],
        limit: 1,
      );
      if (existingTeacher.isNotEmpty) {
        await db.update(
          'teachers',
          {
            'user_id': id,
            'department_id':
                departmentId ?? existingTeacher.first['department_id'],
            'class_id': classId ?? existingTeacher.first['class_id'],
            'updated_at': now,
            'sync_status': 'PENDING',
          },
          where: 'id = ?',
          whereArgs: [existingTeacher.first['id']],
        );
      } else {
        final teacherId = UuidUtils.generate();
        await db.insert('teachers', {
          'id': teacherId,
          'user_id': id,
          'name': displayName.trim(),
          'subject': 'General',
          'email': cleanEmail,
          'username': username.trim(),
          'password': '',
          'class_id': classId,
          'department_id': departmentId,
          'is_active': 1,
          'employee_code': employeeId?.trim().isNotEmpty == true
              ? employeeId!.trim()
              : 'FAC-${id.substring(0, 8)}',
          'designation':
              role == UserRole.hod ? 'Head of Department' : 'Instructor',
          'created_at': now,
          'updated_at': now,
          'sync_status': 'PENDING',
          'is_deleted': 0,
        });
        SyncService.instance.schedulePush(
          'teachers',
          idColumn: 'id',
          idValue: teacherId,
        );
      }
    }

    // If student, check if student profile exists or create one
    if (role == UserRole.student && rollNo != null && rollNo.trim().isNotEmpty) {
      final existingStudent = await db.query(
        'students',
        where: 'roll_number = ? OR roll_no = ?',
        whereArgs: [rollNo.trim(), rollNo.trim()],
        limit: 1,
      );
      if (existingStudent.isEmpty && classId != null) {
        final studentId = UuidUtils.generate();
        await db.insert('students', {
          'id': studentId,
          'name': displayName.trim(),
          'roll_number': rollNo.trim(),
          'roll_no': rollNo.trim(),
          'class_id': classId,
          'department_id': departmentId,
          'current_year': '1st Year',
          'is_active': 1,
          'status': 'ACTIVE',
          'created_at': now,
          'updated_at': now,
          'sync_status': 'PENDING',
          'is_deleted': 0,
        });
        SyncService.instance.schedulePush(
          'students',
          idColumn: 'id',
          idValue: studentId,
        );
      }
    }

    return User.fromMap(userMap);
  }

  /// Toggles suspension status for a user.
  Future<void> toggleSuspension(
    String userId, {
    required bool suspend,
    String? reason,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'users',
      {
        'is_suspended': suspend ? 1 : 0,
        'suspended_at': suspend ? now : null,
        'suspended_reason':
            suspend ? (reason ?? 'Suspended by Administrator') : null,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    SyncService.instance.schedulePush('users', idColumn: 'id', idValue: userId);
  }

  /// Updates a user's role and synchronizes with the RBAC user_roles catalogue.
  Future<void> updateUserRole(String userId, UserRole newRole) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'users',
      {
        'role': newRole.value,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    SyncService.instance.schedulePush('users', idColumn: 'id', idValue: userId);

    final roleRows = await db.query(
      'roles',
      where: 'code = ? AND is_deleted = 0',
      whereArgs: [newRole.value],
      limit: 1,
    );
    if (roleRows.isNotEmpty) {
      final roleId = roleRows.first['id'] as String;
      await db.update(
        'user_roles',
        {'is_deleted': 1, 'updated_at': now},
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      final newId = UuidUtils.generate();
      await db.insert('user_roles', {
        'id': newId,
        'user_id': userId,
        'role_id': roleId,
        'institute_id': AppConstants.defaultInstituteId,
        'assigned_at': now,
        'sync_status': 'PENDING',
        'is_deleted': 0,
      });
      SyncService.instance.schedulePush(
        'user_roles',
        idColumn: 'id',
        idValue: newId,
      );
    }
  }

  /// Assigns a teacher to a department and/or primary class.
  Future<void> assignTeacherDetails({
    required String userId,
    String? departmentId,
    String? classId,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'teachers',
      {
        'department_id': departmentId,
        'class_id': classId,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    if (departmentId != null) {
      await db.delete(
        'user_departments',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      final deptAssignmentId = UuidUtils.generate();
      await db.insert('user_departments', {
        'id': deptAssignmentId,
        'user_id': userId,
        'department_id': departmentId,
        'created_at': now,
        'sync_status': 'PENDING',
        'is_deleted': 0,
      });
      SyncService.instance.schedulePush(
        'user_departments',
        idColumn: 'id',
        idValue: deptAssignmentId,
      );
    }
  }
}
