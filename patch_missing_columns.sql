-- =============================================================================
-- patch_missing_columns.sql
-- =============================================================================
-- Adds any missing payload columns to EXISTING Supabase tables.
--
-- Source of truth: every field returned by toSupabaseJson() in
-- lib/core/models/ (11 tables / 123 fields, extracted programmatically).
--
-- Statement format (idempotent, safe to re-run):
--   ALTER TABLE <table_name> ADD COLUMN IF NOT EXISTS <column> <DATA_TYPE>;
--
-- Type mapping (identical to supabase_schema.sql):
--   Dart String  -> TEXT (including ISO-8601 timestamps and 'YYYY-MM-DD'
--                   dates; matches what the app actually sends)
--   Dart bool    -> BOOLEAN
--   Dart int     -> INTEGER
--   Dart double  -> DOUBLE PRECISION
--   canonical id -> UUID  (no-op when the column already exists)
--
-- No NOT NULL / DEFAULT / PRIMARY KEY constraints here on purpose: ADD COLUMN
-- NOT NULL fails on tables that already contain rows, and a patch must never
-- break a populated database. Constrainted DDL lives in supabase_schema.sql.
--
-- Prerequisite: all 11 tables must already exist (this script only patches
-- columns; it does not create tables).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- departments  (Department.toSupabaseJson — 8 fields)
-- -----------------------------------------------------------------------------
ALTER TABLE departments ADD COLUMN IF NOT EXISTS id UUID;
ALTER TABLE departments ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE departments ADD COLUMN IF NOT EXISTS code TEXT;
ALTER TABLE departments ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE departments ADD COLUMN IF NOT EXISTS is_active BOOLEAN;
ALTER TABLE departments ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE departments ADD COLUMN IF NOT EXISTS updated_at TEXT;
ALTER TABLE departments ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;

-- -----------------------------------------------------------------------------
-- academic_sessions  (AcademicSession.toSupabaseJson — 8 fields)
-- -----------------------------------------------------------------------------
ALTER TABLE academic_sessions ADD COLUMN IF NOT EXISTS id UUID;
ALTER TABLE academic_sessions ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE academic_sessions ADD COLUMN IF NOT EXISTS start_date TEXT;
ALTER TABLE academic_sessions ADD COLUMN IF NOT EXISTS end_date TEXT;
ALTER TABLE academic_sessions ADD COLUMN IF NOT EXISTS is_current BOOLEAN;
ALTER TABLE academic_sessions ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE academic_sessions ADD COLUMN IF NOT EXISTS updated_at TEXT;
ALTER TABLE academic_sessions ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;

-- -----------------------------------------------------------------------------
-- users  (User.toSupabaseJson — 8 fields; password_hash is never pushed)
-- -----------------------------------------------------------------------------
ALTER TABLE users ADD COLUMN IF NOT EXISTS id UUID;
ALTER TABLE users ADD COLUMN IF NOT EXISTS username TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS role TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;

-- -----------------------------------------------------------------------------
-- classes  (SchoolClass.toSupabaseJson — 12 fields)
-- -----------------------------------------------------------------------------
ALTER TABLE classes ADD COLUMN IF NOT EXISTS id UUID;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS local_id INTEGER;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS section TEXT;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS room TEXT;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS class_name TEXT;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS current_year TEXT;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS department_id TEXT;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS academic_session_id TEXT;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS updated_at TEXT;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;

-- -----------------------------------------------------------------------------
-- teachers  (Teacher.toSupabaseJson — 14 fields; password is never pushed)
-- -----------------------------------------------------------------------------
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS id UUID;
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS local_id INTEGER;
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS subject TEXT;
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS username TEXT;
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS class_id INTEGER;
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS is_active BOOLEAN;
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS employee_code TEXT;
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS designation TEXT;
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS department_id TEXT;
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS updated_at TEXT;
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;

-- -----------------------------------------------------------------------------
-- students  (Student.toSupabaseJson — 15 fields)
-- -----------------------------------------------------------------------------
ALTER TABLE students ADD COLUMN IF NOT EXISTS id UUID;
ALTER TABLE students ADD COLUMN IF NOT EXISTS local_id INTEGER;
ALTER TABLE students ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS roll_number TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS class_id INTEGER;
ALTER TABLE students ADD COLUMN IF NOT EXISTS is_active BOOLEAN;
ALTER TABLE students ADD COLUMN IF NOT EXISTS registration_no TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS father_name TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS department_id TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS academic_session_id TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS current_year TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS status TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS updated_at TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;

-- -----------------------------------------------------------------------------
-- subjects  (Subject.toSupabaseJson — 15 fields)
-- -----------------------------------------------------------------------------
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS id UUID;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS local_id INTEGER;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS code TEXT;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS teacher_name TEXT;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS class_id INTEGER;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS department_id TEXT;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS academic_session_id TEXT;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS year TEXT;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS subject_type TEXT;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS contact_hours DOUBLE PRECISION;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS teacher_id INTEGER;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS updated_at TEXT;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;

-- -----------------------------------------------------------------------------
-- attendance_sessions  (AttendanceSession.toSupabaseJson — 13 fields)
-- -----------------------------------------------------------------------------
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS id UUID;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS subject_code TEXT;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS department_id TEXT;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS faculty_id TEXT;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS session_date TEXT;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS academic_session_id TEXT;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS class_id INTEGER;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS year TEXT;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS subject_id INTEGER;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS remarks TEXT;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS updated_at TEXT;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;

-- -----------------------------------------------------------------------------
-- attendance_records  (AttendanceRecord.toSupabaseJson — 10 fields)
-- -----------------------------------------------------------------------------
ALTER TABLE attendance_records ADD COLUMN IF NOT EXISTS id UUID;
ALTER TABLE attendance_records ADD COLUMN IF NOT EXISTS session_id TEXT;
ALTER TABLE attendance_records ADD COLUMN IF NOT EXISTS student_id INTEGER;
ALTER TABLE attendance_records ADD COLUMN IF NOT EXISTS date TEXT;
ALTER TABLE attendance_records ADD COLUMN IF NOT EXISTS status TEXT;
ALTER TABLE attendance_records ADD COLUMN IF NOT EXISTS check_in_time TEXT;
ALTER TABLE attendance_records ADD COLUMN IF NOT EXISTS check_out_time TEXT;
ALTER TABLE attendance_records ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE attendance_records ADD COLUMN IF NOT EXISTS updated_at TEXT;
ALTER TABLE attendance_records ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;

-- -----------------------------------------------------------------------------
-- leave_requests  (LeaveRequest.toSupabaseJson — 10 fields)
-- -----------------------------------------------------------------------------
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS id UUID;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS requester_name TEXT;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS leave_type TEXT;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS start_date TEXT;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS end_date TEXT;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS reason TEXT;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS status TEXT;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS updated_at TEXT;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;

-- -----------------------------------------------------------------------------
-- lab_inventory  (LabInventory.toSupabaseJson — 10 fields)
-- -----------------------------------------------------------------------------
ALTER TABLE lab_inventory ADD COLUMN IF NOT EXISTS id UUID;
ALTER TABLE lab_inventory ADD COLUMN IF NOT EXISTS item_name TEXT;
ALTER TABLE lab_inventory ADD COLUMN IF NOT EXISTS department_id TEXT;
ALTER TABLE lab_inventory ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE lab_inventory ADD COLUMN IF NOT EXISTS current_stock DOUBLE PRECISION;
ALTER TABLE lab_inventory ADD COLUMN IF NOT EXISTS unit TEXT;
ALTER TABLE lab_inventory ADD COLUMN IF NOT EXISTS reorder_level DOUBLE PRECISION;
ALTER TABLE lab_inventory ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE lab_inventory ADD COLUMN IF NOT EXISTS updated_at TEXT;
ALTER TABLE lab_inventory ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;

-- -----------------------------------------------------------------------------
-- institute_id — REQUIRED EXTRA (not part of toSupabaseJson: SyncService
-- stamps it onto every payload centrally before upserting, so the column must
-- exist on all 11 tables or every push would fail with "column not found").
-- -----------------------------------------------------------------------------
ALTER TABLE departments ADD COLUMN IF NOT EXISTS institute_id TEXT;
ALTER TABLE academic_sessions ADD COLUMN IF NOT EXISTS institute_id TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS institute_id TEXT;
ALTER TABLE classes ADD COLUMN IF NOT EXISTS institute_id TEXT;
ALTER TABLE teachers ADD COLUMN IF NOT EXISTS institute_id TEXT;
ALTER TABLE students ADD COLUMN IF NOT EXISTS institute_id TEXT;
ALTER TABLE subjects ADD COLUMN IF NOT EXISTS institute_id TEXT;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS institute_id TEXT;
ALTER TABLE attendance_records ADD COLUMN IF NOT EXISTS institute_id TEXT;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS institute_id TEXT;
ALTER TABLE lab_inventory ADD COLUMN IF NOT EXISTS institute_id TEXT;

-- Tell PostgREST to reload its schema cache so the new columns are usable
-- immediately without waiting for the periodic refresh.
NOTIFY pgrst, 'reload schema';