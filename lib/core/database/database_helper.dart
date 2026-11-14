import 'package:sqflite/sqflite.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/database/migrations/migration_helpers.dart';
import 'package:attendance_app/core/database/migrations/schema_migration_v8.dart';
import 'package:attendance_app/core/database/migrations/schema_migration_v9.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  DatabaseHelper._init() : _testDatabase = null;

  /// Creates a [DatabaseHelper] backed by an existing [Database] for testing.
  /// Bypasses file-based `openDatabase` entirely.
  DatabaseHelper.forTesting(this._testDatabase);

  final Database? _testDatabase;
  static Database? _database;

  /// Sets or clears an in-memory database instance for testing.
  static void setTestDatabase(Database? db) {
    _database = db;
  }

  Future<Database> get database async {
    if (_testDatabase != null) return _testDatabase;
    if (_database != null) return _database!;
    _database = await _initDB('gilt_attendance.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final db = await openDatabase(
      filePath,
      version: 10,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onDowngrade: _onDowngrade,
    );
    await db.execute('PRAGMA foreign_keys = ON;');
    await SchemaMigrationV9.execute(db);

    // Safety: ensure `users` has every column expected by User.toMap() /
    // UserRepository, even on databases created before these columns existed
    // or on fresh installs where the creator omitted them. This runs on every
    // open so existing local .db files are healed without crashing.
    await _ensureUsersColumns(db);

    return db;
  }

  /// Adds `roll_no` and `employee_id` to `users` when they are missing.
  /// Uses `PRAGMA table_info(users)` so it is safe to re-run and never fails
  /// on an existing column.
  Future<void> _ensureUsersColumns(Database db) async {
    final info = await db.rawQuery("PRAGMA table_info('users')");
    final columns = info.map((row) => row['name'] as String).toSet();
    await MigrationHelpers.addColumnIfNotExists(db, 'users', 'roll_no', 'TEXT');
    await MigrationHelpers.addColumnIfNotExists(
      db,
      'users',
      'employee_id',
      'TEXT UNIQUE',
    );
    // Ensure `updated_at` default also exists (defensive, mirrors v7/v8).
    if (!columns.contains('updated_at')) {
      await MigrationHelpers.addColumnIfNotExists(
        db,
        'users',
        'updated_at',
        "TEXT NOT NULL DEFAULT (datetime('now'))",
      );
    }
  }

  Future _onCreate(Database db, int version) async {
    await FreshDatabaseCreator.createAndSeed(db);
    await SchemaMigrationV9.execute(db);
  }


  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Additive migrations only - never drop tables
    if (oldVersion < 7) {
      if (oldVersion < 6) {
        // Handled as needed
      }
    }
    if (oldVersion < 8) {
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'roll_no', 'TEXT',
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'employee_id', 'TEXT UNIQUE',
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'display_name', "TEXT NOT NULL DEFAULT ''",
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'role', "TEXT NOT NULL DEFAULT 'admin'",
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'is_deleted', 'INTEGER NOT NULL DEFAULT 0',
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'is_default_password', 'INTEGER NOT NULL DEFAULT 0',
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'suspended_reason', 'TEXT',
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'failed_login_attempts', 'INTEGER NOT NULL DEFAULT 0',
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'locked_until', 'TEXT',
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'password_changed_at', 'TEXT',
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'last_login_at', 'TEXT',
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'session_expires_at', 'TEXT',
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'auth_user_id', 'TEXT',
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'institute_id',
        "TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}'",
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'is_synced', 'INTEGER NOT NULL DEFAULT 0',
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'sync_status', "TEXT NOT NULL DEFAULT 'PENDING'",
      );
      await MigrationHelpers.addColumnIfNotExists(
        db, 'users', 'updated_at', "TEXT NOT NULL DEFAULT (datetime('now'))",
      );
      await db.execute('''CREATE TABLE IF NOT EXISTS password_reset_codes (
        email TEXT PRIMARY KEY,
        code_hash TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        used_at TEXT,
        expires_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )''');
    }
    if (oldVersion < 9) {
      await SchemaMigrationV9.execute(db);
    }
    if (oldVersion < 10) {
      // v8 adds sync_queue.status / next_retry_at for capped retries and the
      // quarantine dead-letter queue (applied once on upgrade).
      await SchemaMigrationV8.execute(db);
    }
    await db.execute('PRAGMA foreign_keys = ON;');
  }

  Future _onDowngrade(Database db, int oldVersion, int newVersion) async {
    await db.execute('PRAGMA foreign_keys = ON;');
  }

  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(table, data);
  }

  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async {
    final db = await database;
    return await db.query(table, where: where, whereArgs: whereArgs, orderBy: orderBy);
  }

  Future<int> update(
    String table, {
    required Map<String, dynamic> data,
    required String where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return await db.update(table, data, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(
    String table, {
    required String where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future close() async {
    final db = await database;
    db.close();
    _database = null;
  }
}