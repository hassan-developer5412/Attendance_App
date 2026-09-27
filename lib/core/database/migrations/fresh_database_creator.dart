import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/migrations/migration_helpers.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

class FreshDatabaseCreator {
  FreshDatabaseCreator._();

  static Future<void> createAndSeed(Database db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE departments (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        display_name TEXT NOT NULL,
        email TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'admin',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE classes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        section TEXT NOT NULL,
        room TEXT NOT NULL,
        department_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE teachers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        subject TEXT NOT NULL,
        email TEXT NOT NULL DEFAULT '',
        username TEXT NOT NULL DEFAULT '',
        password TEXT NOT NULL DEFAULT '',
        class_id INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1,
        employee_code TEXT,
        designation TEXT NOT NULL DEFAULT 'Instructor',
        department_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE SET NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        roll_number TEXT NOT NULL,
        class_id INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        roll_no TEXT,
        full_name TEXT,
        registration_no TEXT,
        father_name TEXT NOT NULL DEFAULT '',
        department_id TEXT,
        current_semester TEXT NOT NULL DEFAULT '1st',
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE subjects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        code TEXT NOT NULL,
        teacher_name TEXT NOT NULL,
        class_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE attendance_sessions (
        id TEXT PRIMARY KEY,
        subject_code TEXT NOT NULL DEFAULT '',
        department_id TEXT NOT NULL DEFAULT '',
        faculty_id TEXT NOT NULL DEFAULT '',
        session_date TEXT NOT NULL,
        remarks TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE attendance_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        session_id TEXT,
        student_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        status TEXT NOT NULL,
        check_in_time TEXT,
        check_out_time TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        UNIQUE (student_id, date)
      )
    ''');

    batch.execute('''
      CREATE TABLE leave_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        requester_name TEXT NOT NULL,
        leave_type TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        reason TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE lab_inventory (
        id TEXT PRIMARY KEY,
        item_name TEXT NOT NULL,
        department_id TEXT NOT NULL,
        category TEXT NOT NULL,
        current_stock REAL NOT NULL DEFAULT 0,
        unit TEXT NOT NULL DEFAULT 'pcs',
        reorder_level REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE sync_queue (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');

    await batch.commit(noResult: true);

    final passwordHash = sha256
        .convert(utf8.encode(AppConstants.defaultAdminPassword))
        .toString();

    final adminUuid = UuidUtils.deterministic('users', 'admin');
    await db.insert('users', {
      'uuid': adminUuid,
      'username': AppConstants.defaultAdminUsername,
      'password_hash': passwordHash,
      'display_name': AppConstants.defaultAdminDisplayName,
      'email': AppConstants.defaultAdminEmail,
      'role': UserRole.admin.value,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'SYNCED',
      'is_deleted': 0,
    });

    await MigrationHelpers.seedDepartments(db);
  }
}
