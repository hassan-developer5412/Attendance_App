import 'package:sqflite/sqflite.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_platform.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/database/migrations/schema_migration_v3.dart';
import 'package:attendance_app/core/database/migrations/schema_migration_v4.dart';
import 'package:attendance_app/core/database/migrations/schema_migration_v5.dart';

/// Singleton helper that manages the SQLite database lifecycle.
///
/// Handles schema creation, migrations, and provides the shared [Database]
/// instance to all stores.
class DatabaseHelper {
  DatabaseHelper._internal();

  DatabaseHelper.forTesting(Database db) : _database = db;

  static final DatabaseHelper instance = DatabaseHelper._internal();

  Database? _database;

  /// Returns the shared database instance, initializing it on first access.
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = await databaseFilePath(AppConstants.databaseName);

    return openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Enable foreign key support.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Migrate schema for existing databases without data loss.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE teachers ADD COLUMN email TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE teachers ADD COLUMN username TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE teachers ADD COLUMN password TEXT NOT NULL DEFAULT ''",
      );
    }

    if (oldVersion < 3) {
      await SchemaMigrationV3.execute(db);
    }

    if (oldVersion < 4) {
      await SchemaMigrationV4.execute(db);
    }

    if (oldVersion < 5) {
      await SchemaMigrationV5.execute(db);
    }
  }

  /// Create all tables and seed the default admin user.
  Future<void> _onCreate(Database db, int version) async {
    await FreshDatabaseCreator.createAndSeed(db);
  }

  /// Closes the database connection. Call during app teardown if needed.
  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
    }
  }
}
