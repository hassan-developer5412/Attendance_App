import 'package:flutter_test/flutter_test.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/repositories/user_repository.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

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
  await db.execute('''CREATE TABLE IF NOT EXISTS password_reset_codes (
    email TEXT PRIMARY KEY,
    code_hash TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    used_at TEXT,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL
  )''');
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('AuthStore session and guard logic', () {
    late DatabaseHelper dbHelper;
    late UserRepository repo;
    late AuthStore store;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      final db = await openUsersDb();
      dbHelper = DatabaseHelper.forTesting(db);
      repo = UserRepository(dbHelper: dbHelper);
      store = AuthStore(
        userRepository: repo,
        secureStorage: FakeSecureStorage(),
        databaseHelper: dbHelper,
      );
    });

    tearDown(() async {
      await store.logout(clearSecure: true);
      await dbHelper.close();
    });

    Future<String> insertActiveUser({
      required String username,
      required String password,
      String? rollNo,
      String? employeeId,
      String email = '',
      bool isSuspended = false,
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
        'role': 'teacher',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'SYNCED',
        'is_deleted': 0,
        'is_suspended': isSuspended ? 1 : 0,
      });
      return id;
    }    test('login stores session tokens in secure storage', () async {
      await insertActiveUser(username: 'jsmith', password: 'Pass123!');

      final user = await store.login('jsmith', 'Pass123!');
      expect(user, isNotNull);
      expect(store.isLoggedIn, isTrue);

      final storedId = await store.sessionStorage.read(key: 'session_user_id');
      expect(storedId, equals(user!.id));
      final storedRole = await store.sessionStorage.read(key: 'session_user_role');
      expect(storedRole, equals('teacher'));
      final storedExpires = await store.sessionStorage.read(key: 'session_expires_at');
      expect(storedExpires, isNotNull);
    });

    test('login blocks suspended account', () async {
      await insertActiveUser(
        username: 'suspended',
        password: 'Pass123!',
        isSuspended: true,
      );

      final user = await store.login('suspended', 'Pass123!');
      expect(user, isNull);
      expect(store.isLoggedIn, isFalse);
      expect(store.lastAuthError, contains('suspended'));
    });

    test('login blocks locked account', () async {
      final id = UuidUtils.generate();
      final hash = BCrypt.hashpw('Pass123!', BCrypt.gensalt());
      final lockUntil =
          DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String();
      await dbHelper.insert('users', {
        'id': id,
        'username': 'locked',
        'roll_no': null,
        'employee_id': null,
        'password_hash': hash,
        'display_name': 'Locked',
        'email': '',
        'role': 'teacher',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'SYNCED',
        'is_deleted': 0,
        'failed_login_attempts': 5,
        'locked_until': lockUntil,
      });

      final user = await store.login('locked', 'Pass123!');
      expect(user, isNull);
      expect(store.lastAuthError, contains('locked'));
    });

    test('init restores session from secure storage', () async {
      await insertActiveUser(username: 'jsmith', password: 'Pass123!');

      final user = await store.login('jsmith', 'Pass123!');
      expect(user, isNotNull);

      final storage = store.sessionStorage;
      final store2 = AuthStore(
        userRepository: repo,
        secureStorage: storage,
        databaseHelper: dbHelper,
      );
      await store2.init();

      expect(store2.isLoggedIn, isTrue);
      expect(store2.currentUser?.username, equals('jsmith'));
    });

    test('init rejects restored session when account is suspended in DB', () async {
      final id = await insertActiveUser(username: 'jsmith', password: 'Pass123!');

      final user = await store.login('jsmith', 'Pass123!');
      expect(user, isNotNull);

      await dbHelper.update(
        'users',
        data: {
          'is_suspended': 1,
          'suspended_at': DateTime.now().toUtc().toIso8601String(),
          'suspended_reason': 'Policy violation',
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      final storage = store.sessionStorage;
      final store2 = AuthStore(
        userRepository: repo,
        secureStorage: storage,
        databaseHelper: dbHelper,
      );
      await store2.init();

      expect(store2.isLoggedIn, isFalse);
      expect(store2.lastAuthError, contains('suspended'));
    });

    test('validateSession blocks after DB marks account suspended', () async {
      await insertActiveUser(username: 'jsmith', password: 'Pass123!');

      final user = await store.login('jsmith', 'Pass123!');
      expect(user, isNotNull);
      expect(store.isLoggedIn, isTrue);

      await dbHelper.update(
        'users',
        data: {'is_suspended': 1},
        where: 'id = ?',
        whereArgs: [user!.id],
      );

      final stillValid = await store.validateSession();
      expect(stillValid, isFalse);
      expect(store.isLoggedIn, isFalse);
      expect(store.lastAuthError, contains('suspended'));
    });

    test('validateSession keeps active session valid', () async {
      await insertActiveUser(username: 'jsmith', password: 'Pass123!');

      final user = await store.login('jsmith', 'Pass123!');
      expect(user, isNotNull);

      final stillValid = await store.validateSession();
      expect(stillValid, isTrue);
      expect(store.isLoggedIn, isTrue);
    });

    test('requestPasswordReset issues OTP for existing email', () async {
      await insertActiveUser(
        username: 'jsmith',
        password: 'Pass123!',
        email: 'jsmith@institute.edu',
      );

      final sent = await store.requestPasswordReset('jsmith@institute.edu');
      expect(sent, isTrue);
      expect(store.lastSentOtp, isNotNull);
      expect(store.lastSentOtp!.length, equals(6));
    });

    test('requestPasswordReset returns false for unknown email', () async {
      final sent = await store.requestPasswordReset('nobody@institute.edu');
      expect(sent, isFalse);
    });

    test('resetPasswordWithOtp succeeds with valid code', () async {
      await insertActiveUser(
        username: 'jsmith',
        password: 'OldPass1!',
        email: 'jsmith@institute.edu',
      );

      final sent = await store.requestPasswordReset('jsmith@institute.edu');
      expect(sent, isTrue);

      final otp = store.lastSentOtp!;
      final reset = await store.resetPasswordWithOtp(
        'jsmith@institute.edu',
        otp,
        'NewPass123!',
      );
      expect(reset, isTrue);

      final login1 = await store.login('jsmith', 'OldPass1!');
      expect(login1, isNull);

      final login2 = await store.login('jsmith', 'NewPass123!');
      expect(login2, isNotNull);
    });

    test('resetPasswordWithOtp rejects wrong code', () async {
      await insertActiveUser(
        username: 'jsmith',
        password: 'Pass123!',
        email: 'jsmith@institute.edu',
      );

      await store.requestPasswordReset('jsmith@institute.edu');

      final reset = await store.resetPasswordWithOtp(
        'jsmith@institute.edu',
        '000000',
        'NewPass123!',
      );
      expect(reset, isFalse);
    });

    test('logout clears secure storage session', () async {
      await insertActiveUser(username: 'jsmith', password: 'Pass123!');

      await store.login('jsmith', 'Pass123!');
      expect(store.isLoggedIn, isTrue);

      await store.logout(clearSecure: true);
      expect(store.isLoggedIn, isFalse);

      final storedId = await store.sessionStorage.read(key: 'session_user_id');
      expect(storedId, isNull);
    });
  });
}