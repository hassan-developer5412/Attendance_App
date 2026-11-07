import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/repositories/user_repository.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Opens an empty in-memory database with the full v8 `users` table.
Future<Database> openUsersDb() async {
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
  await db.execute('''CREATE TABLE users (
    id TEXT PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    roll_no TEXT,
    employee_id TEXT UNIQUE,
    password_hash TEXT NOT NULL,
    display_name TEXT NOT NULL,
    email TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'admin',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_status TEXT NOT NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
    is_synced INTEGER NOT NULL DEFAULT 0,
    auth_user_id TEXT,
    is_default_password INTEGER DEFAULT 0,
    is_suspended INTEGER DEFAULT 0,
    suspended_at TEXT,
    suspended_reason TEXT,
    failed_login_attempts INTEGER DEFAULT 0,
    locked_until TEXT,
    password_changed_at TEXT,
    last_login_at TEXT,
    session_expires_at TEXT
  )''');
  return db;
}

void main() {
  group('UserRepository offline authentication', () {
    late DatabaseHelper dbHelper;
    late UserRepository repo;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      final db = await openUsersDb();
      dbHelper = DatabaseHelper.forTesting(db);
      repo = UserRepository(dbHelper: dbHelper);
    });

    tearDown(() async {
      await dbHelper.close();
    });

    Future<String> insertUser({
      required String username,
      required String password,
      String? rollNo,
      String? employeeId,
      String email = '',
      bool isSuspended = false,
      int failedAttempts = 0,
      String? lockedUntil,
      String role = 'teacher',
    }) async {
      final id = UuidUtils.generate();
      final hash = BCrypt.hashpw(password, BCrypt.gensalt());
      await dbHelper.insert('users', {
        'id': id,
        'username': username,
        'roll_no': rollNo,
        'employee_id': employeeId,
        'password_hash': hash,
        'display_name': username,
        'email': email,
        'role': role,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'SYNCED',
        'is_deleted': 0,
        'is_suspended': isSuspended ? 1 : 0,
        'failed_login_attempts': failedAttempts,
        'locked_until': lockedUntil,
      });
      return id;
    }    test('authenticates by username with bcrypt', () async {
      await insertUser(username: 'jsmith', password: 'SecurePass1!');

      final result = await repo.authenticate('jsmith', 'SecurePass1!');
      expect(result, isNotNull);
      expect(result!.user.username, equals('jsmith'));
      expect(result.wasLegacyHash, isFalse);
    });

    test('authenticates by roll number', () async {
      await insertUser(
        username: 'student1',
        password: 'Pass123!',
        rollNo: 'CIT-2025-001',
      );

      final result = await repo.authenticate('CIT-2025-001', 'Pass123!');
      expect(result, isNotNull);
      expect(result!.user.username, equals('student1'));
    });

    test('authenticates by employee ID', () async {
      await insertUser(
        username: 'jdoe',
        password: 'Pass123!',
        employeeId: 'EMP-10042',
      );

      final result = await repo.authenticate('EMP-10042', 'Pass123!');
      expect(result, isNotNull);
      expect(result!.user.username, equals('jdoe'));
    });

    test('rejects wrong password', () async {
      await insertUser(username: 'jsmith', password: 'SecurePass1!');

      final result = await repo.authenticate('jsmith', 'WrongPass!');
      expect(result, isNull);
    });

    test('rejects unknown identifier', () async {
      await insertUser(username: 'jsmith', password: 'SecurePass1!');

      final result = await repo.authenticate('nonexistent', 'SecurePass1!');
      expect(result, isNull);
    });

    test('blocks suspended account without checking password', () async {
      await insertUser(
        username: 'suspended',
        password: 'SecurePass1!',
        isSuspended: true,
      );

      final result = await repo.authenticate('suspended', 'SecurePass1!');
      expect(result, isNotNull);
      expect(result!.isSuspended, isTrue);
      expect(result.user.isSuspended, isTrue);
    });

    test('blocks locked account after failed attempts', () async {
      final lockUntil =
          DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String();
      await insertUser(
        username: 'locked',
        password: 'SecurePass1!',
        failedAttempts: 5,
        lockedUntil: lockUntil,
      );

      final result = await repo.authenticate('locked', 'SecurePass1!');
      expect(result, isNotNull);
      expect(result!.isLocked, isTrue);
      expect(result.user.isLocked, isTrue);
    });

    test('upgrades legacy SHA-256 hash to bcrypt on successful login', () async {
      final id = UuidUtils.generate();
      final shaHash = sha256.convert(utf8.encode('LegacyPass!')).toString();
      await dbHelper.insert('users', {
        'id': id,
        'username': 'legacy',
        'roll_no': null,
        'employee_id': null,
        'password_hash': shaHash,
        'display_name': 'Legacy',
        'email': '',
        'role': 'admin',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'SYNCED',
        'is_deleted': 0,
      });

      final result = await repo.authenticate('legacy', 'LegacyPass!');
      expect(result, isNotNull);
      expect(result!.wasLegacyHash, isTrue);

      final row = await dbHelper.query('users', where: 'id = ?', whereArgs: [id]);
      final newHash = row.first['password_hash'] as String;
      expect(newHash, startsWith(r'$2'));
      expect(BCrypt.checkpw('LegacyPass!', newHash), isTrue);
    });

    test('getByEmail returns user by email case-insensitively', () async {
      await insertUser(
        username: 'jsmith',
        password: 'Pass123!',
        email: 'JSmith@Institute.edu',
      );

      final byLower = await repo.getByEmail('jsmith@institute.edu');
      expect(byLower, isNotNull);
      expect(byLower!.username, equals('jsmith'));

      final byMixed = await repo.getByEmail('JSMITH@INSTITUTE.EDU');
      expect(byMixed, isNotNull);
      expect(byMixed!.username, equals('jsmith'));

      final missing = await repo.getByEmail('nobody@institute.edu');
      expect(missing, isNull);
    });

    test('counts failed attempts and locks after threshold', () async {
      final id = await insertUser(username: 'attempts', password: 'Pass123!');

      for (var i = 0; i < 4; i++) {
        await repo.authenticate('attempts', 'WrongPass');
      }
      final user4 = await repo.getById(id);
      expect(user4!.failedLoginAttempts, equals(4));
      expect(user4.isLocked, isFalse);

      await repo.authenticate('attempts', 'WrongPass');
      final user5 = await repo.getById(id);
      expect(user5!.failedLoginAttempts, equals(5));
      expect(user5.isLocked, isTrue);
      expect(user5.lockedUntil, isNotNull);
    });

    test('clears failed attempts on successful login', () async {
      final id = await insertUser(username: 'clears', password: 'Pass123!');

      await repo.authenticate('clears', 'WrongPass');
      await repo.authenticate('clears', 'Pass123!');

      final user = await repo.getById(id);
      expect(user!.failedLoginAttempts, equals(0));
      expect(user.lockedUntil, isNull);
      expect(user.lastLoginAt, isNotNull);
    });
  });
}