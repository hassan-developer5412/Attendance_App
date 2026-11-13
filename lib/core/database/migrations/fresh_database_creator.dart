import 'package:sqflite/sqflite.dart';
import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/migrations/migration_helpers.dart';

/// Creates the full v7 database schema from scratch.
///
/// Fresh installs start with an empty `users` table — no default admin
/// credentials are seeded. Canonical departments and academic sessions are
/// still seeded idempotently.
///
/// All tables use `TEXT PRIMARY KEY` holding a client-generated v4 UUID.
/// There are no more `INTEGER PRIMARY KEY AUTOINCREMENT` columns.
class FreshDatabaseCreator {
  FreshDatabaseCreator._();

  static Future<void> createAndSeed(Database db) async {

    final batch = db.batch();

    // ── departments ──────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE departments (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT NOT NULL UNIQUE,
        description TEXT NOT NULL DEFAULT '',
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── academic_sessions ────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE academic_sessions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        is_current INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── users ────────────────────────────────────────────────────────────────
    // id is now TEXT UUID (no more INTEGER AUTOINCREMENT + uuid column).
    batch.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
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
      )
    ''');

    // ── classes ──────────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE classes (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        section TEXT NOT NULL,
        room TEXT NOT NULL,
        class_name TEXT NOT NULL DEFAULT '',
        current_year TEXT NOT NULL DEFAULT '',
        department_id TEXT,
        academic_session_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── teachers ─────────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE teachers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        subject TEXT NOT NULL,
        email TEXT NOT NULL DEFAULT '',
        username TEXT NOT NULL DEFAULT '',
        password TEXT NOT NULL DEFAULT '',
        class_id TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        employee_code TEXT,
        designation TEXT NOT NULL DEFAULT 'Instructor',
        department_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
        is_synced INTEGER NOT NULL DEFAULT 0,
        user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE SET NULL
      )
    ''');

    // ── students ─────────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE students (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        roll_number TEXT NOT NULL,
        class_id TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        roll_no TEXT,
        full_name TEXT,
        registration_no TEXT,
        father_name TEXT NOT NULL DEFAULT '',
        department_id TEXT,
        academic_session_id TEXT,
        current_year TEXT NOT NULL DEFAULT '1st Year',
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    // ── subjects ─────────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE subjects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT NOT NULL,
        teacher_name TEXT NOT NULL,
        class_id TEXT NOT NULL,
        department_id TEXT,
        academic_session_id TEXT,
        year TEXT NOT NULL DEFAULT '',
        subject_type TEXT NOT NULL DEFAULT 'THEORY',
        contact_hours REAL NOT NULL DEFAULT 0,
        teacher_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    // ── attendance_sessions ───────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE attendance_sessions (
        id TEXT PRIMARY KEY,
        subject_code TEXT NOT NULL DEFAULT '',
        department_id TEXT NOT NULL DEFAULT '',
        faculty_id TEXT NOT NULL DEFAULT '',
        session_date TEXT NOT NULL,
        academic_session_id TEXT NOT NULL DEFAULT '',
        class_id TEXT,
        year TEXT NOT NULL DEFAULT '',
        subject_id TEXT,
        remarks TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── attendance_records ───────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE attendance_records (
        id TEXT PRIMARY KEY,
        session_id TEXT,
        student_id TEXT NOT NULL,
        date TEXT NOT NULL,
        status TEXT NOT NULL,
        check_in_time TEXT,
        check_out_time TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        UNIQUE (session_id, student_id)
      )
    ''');

    // ── leave_requests ───────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE leave_requests (
        id TEXT PRIMARY KEY,
        requester_name TEXT NOT NULL,
        leave_type TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        reason TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── lab_inventory ────────────────────────────────────────────────────────
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
        is_deleted INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── sync_queue ───────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE sync_queue (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        status TEXT NOT NULL DEFAULT 'PENDING',
        next_retry_at TEXT
      )
    ''');

    await batch.commit(noResult: true);

    // ── Supporting indexes ────────────────────────────────────────────────
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_users_auth_user_id
      ON users(auth_user_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_teachers_user_id
      ON teachers(user_id)
    ''');

    await MigrationHelpers.seedDepartments(db);
    await MigrationHelpers.seedAcademicSessions(db);
  }
}
