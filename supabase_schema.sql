-- =============================================================================
-- supabase_schema.sql — Cloud schema for the Attendance_APP Supabase sync
-- =============================================================================
-- Generated from the 11 toSupabaseJson() payload contracts in lib/core/models/
-- (same list as SchemaMigrationV5.syncedTables).
--
-- TYPE MAPPING (payload value -> column type):
--   id                canonical UUID string      -> id UUID PRIMARY KEY
--   local_id          legacy integer row id      -> INTEGER  (classes, teachers,
--                      students, subjects only; pairs with integer FK columns
--                      such as class_id / student_id / teacher_id)
--   Dart bool         JSON true/false            -> BOOLEAN
--   Dart double       JSON number                -> DOUBLE PRECISION
--   Dart int          JSON number                -> INTEGER
--   Dart DateTime     ISO-8601 string            -> TEXT (kept as TEXT so
--                      PostgREST upserts can never fail a timestamp cast;
--                      switch to TIMESTAMPTZ later if you want server-side
--                      time handling — values are already ISO-8601)
--
-- DELIBERATELY EXCLUDED (local-only, never sent over the wire):
--   sync_status, is_synced, password, password_hash, legacy alias columns
--   (roll_no, full_name), JOIN-only display fields (student_name, roll_number
--   on attendance reads), and the sync_queue table.
--
-- institute_id is NOT part of toSupabaseJson(): SyncService stamps it onto
-- every payload centrally before upserting.
--
-- SECURITY: RLS is enabled on every table with a fully permissive
--   "Dev Access" policy so anon/authenticated pushes succeed during
--   development. REPLACE THESE POLICIES with institute-scoped, authenticated
--   policies before production (e.g. USING (institute_id = <JWT claim>)).
--
-- Safe to re-run: CREATE TABLE IF NOT EXISTS + DROP POLICY IF EXISTS.
-- Paste this entire file into the Supabase SQL Editor and run it once.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. departments  (Department.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS departments (
  id            UUID PRIMARY KEY,
  name          TEXT NOT NULL,
  code          TEXT NOT NULL,
  description   TEXT NOT NULL DEFAULT '',
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  is_deleted    BOOLEAN NOT NULL DEFAULT false,
  institute_id  TEXT NOT NULL DEFAULT 'default_institute'
);

-- -----------------------------------------------------------------------------
-- 2. academic_sessions  (AcademicSession.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS academic_sessions (
  id            UUID PRIMARY KEY,
  name          TEXT NOT NULL,
  start_date    TEXT NOT NULL,
  end_date      TEXT NOT NULL,
  is_current    BOOLEAN NOT NULL DEFAULT false,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  is_deleted    BOOLEAN NOT NULL DEFAULT false,
  institute_id  TEXT NOT NULL DEFAULT 'default_institute'
);

-- -----------------------------------------------------------------------------
-- 3. users  (User.toSupabaseJson — password_hash is never pushed)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id            UUID PRIMARY KEY,
  username      TEXT NOT NULL,
  display_name  TEXT NOT NULL,
  email         TEXT NOT NULL,
  role          TEXT NOT NULL,               -- 'admin' | 'teacher' | 'student'
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  is_deleted    BOOLEAN NOT NULL DEFAULT false,
  institute_id  TEXT NOT NULL DEFAULT 'default_institute'
);

-- -----------------------------------------------------------------------------
-- 4. classes  (SchoolClass.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS classes (
  id                    UUID PRIMARY KEY,
  local_id              INTEGER NOT NULL,     -- legacy SQLite integer PK
  name                  TEXT NOT NULL,
  section               TEXT NOT NULL,
  room                  TEXT NOT NULL,
  class_name            TEXT NOT NULL,
  current_year          TEXT NOT NULL,
  department_id         TEXT,                 -- nullable FK column (TEXT uuid)
  academic_session_id   TEXT,                 -- nullable FK column (TEXT uuid)
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL,
  is_deleted            BOOLEAN NOT NULL DEFAULT false,
  institute_id          TEXT NOT NULL DEFAULT 'default_institute'
);

-- -----------------------------------------------------------------------------
-- 5. teachers  (Teacher.toSupabaseJson — password is never pushed)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS teachers (
  id              UUID PRIMARY KEY,
  local_id        INTEGER NOT NULL,           -- legacy SQLite integer PK
  name            TEXT NOT NULL,
  subject         TEXT NOT NULL,
  email           TEXT NOT NULL,
  username        TEXT NOT NULL,
  class_id        INTEGER,                    -- nullable local class id
  is_active       BOOLEAN NOT NULL DEFAULT true,
  employee_code   TEXT NOT NULL,
  designation     TEXT NOT NULL,
  department_id   TEXT,                       -- nullable FK column (TEXT uuid)
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  is_deleted      BOOLEAN NOT NULL DEFAULT false,
  institute_id    TEXT NOT NULL DEFAULT 'default_institute'
);

-- -----------------------------------------------------------------------------
-- 6. students  (Student.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS students (
  id                    UUID PRIMARY KEY,
  local_id              INTEGER NOT NULL,     -- legacy SQLite integer PK
  name                  TEXT NOT NULL,
  roll_number           TEXT NOT NULL,
  class_id              INTEGER NOT NULL,     -- local classes.local_id
  is_active             BOOLEAN NOT NULL DEFAULT true,
  registration_no       TEXT NOT NULL,
  father_name           TEXT NOT NULL,
  department_id         TEXT,                 -- nullable FK column (TEXT uuid)
  academic_session_id   TEXT,                 -- nullable FK column (TEXT uuid)
  current_year          TEXT NOT NULL,
  status                TEXT NOT NULL,
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL,
  is_deleted            BOOLEAN NOT NULL DEFAULT false,
  institute_id          TEXT NOT NULL DEFAULT 'default_institute'
);

-- -----------------------------------------------------------------------------
-- 7. subjects  (Subject.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subjects (
  id                    UUID PRIMARY KEY,
  local_id              INTEGER NOT NULL,     -- legacy SQLite integer PK
  name                  TEXT NOT NULL,
  code                  TEXT NOT NULL,
  teacher_name          TEXT NOT NULL,
  class_id              INTEGER NOT NULL,     -- local classes.local_id
  department_id         TEXT,                 -- nullable FK column (TEXT uuid)
  academic_session_id   TEXT,                 -- nullable FK column (TEXT uuid)
  year                  TEXT NOT NULL,
  subject_type          TEXT NOT NULL,        -- 'THEORY' | 'PRACTICAL' | 'BOTH'
  contact_hours         DOUBLE PRECISION NOT NULL,
  teacher_id            INTEGER,              -- nullable local teachers.local_id
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL,
  is_deleted            BOOLEAN NOT NULL DEFAULT false,
  institute_id          TEXT NOT NULL DEFAULT 'default_institute'
);

-- -----------------------------------------------------------------------------
-- 8. attendance_sessions  (AttendanceSession.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS attendance_sessions (
  id                    UUID PRIMARY KEY,
  subject_code          TEXT NOT NULL,
  department_id         TEXT NOT NULL,
  faculty_id            TEXT NOT NULL,
  session_date          TEXT NOT NULL,        -- 'YYYY-MM-DD'
  academic_session_id   TEXT NOT NULL,
  class_id              INTEGER,              -- nullable local classes.local_id
  year                  TEXT NOT NULL,
  subject_id            INTEGER,              -- nullable local subjects.local_id
  remarks               TEXT NOT NULL,
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL,
  is_deleted            BOOLEAN NOT NULL DEFAULT false,
  institute_id          TEXT NOT NULL DEFAULT 'default_institute'
);

-- -----------------------------------------------------------------------------
-- 9. attendance_records  (AttendanceRecord.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS attendance_records (
  id              UUID PRIMARY KEY,
  session_id      TEXT,                       -- attendance_sessions.id (uuid)
  student_id      INTEGER NOT NULL,           -- local students.local_id
  date            TEXT NOT NULL,              -- 'YYYY-MM-DD'
  status          TEXT NOT NULL,              -- 'PRESENT'|'ABSENT'|'LATE'|'LEAVE'
  check_in_time   TEXT,                       -- nullable ISO-8601
  check_out_time  TEXT,                       -- nullable ISO-8601
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  is_deleted      BOOLEAN NOT NULL DEFAULT false,
  institute_id    TEXT NOT NULL DEFAULT 'default_institute'
);

-- -----------------------------------------------------------------------------
-- 10. leave_requests  (LeaveRequest.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS leave_requests (
  id              UUID PRIMARY KEY,
  requester_name  TEXT NOT NULL,
  leave_type      TEXT NOT NULL,
  start_date      TEXT NOT NULL,              -- ISO-8601
  end_date        TEXT NOT NULL,              -- ISO-8601
  reason          TEXT NOT NULL,
  status          TEXT NOT NULL,              -- 'pending'|'approved'|'rejected'
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  is_deleted      BOOLEAN NOT NULL DEFAULT false,
  institute_id    TEXT NOT NULL DEFAULT 'default_institute'
);

-- -----------------------------------------------------------------------------
-- 11. lab_inventory  (LabInventory.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lab_inventory (
  id              UUID PRIMARY KEY,
  item_name       TEXT NOT NULL,
  department_id   TEXT NOT NULL,
  category        TEXT NOT NULL,              -- 'HARDWARE_EQUIPMENT'|'CHEMICAL'|'RAW_MATERIAL'|'MACHINERY_PART'
  current_stock   DOUBLE PRECISION NOT NULL,
  unit            TEXT NOT NULL,
  reorder_level   DOUBLE PRECISION NOT NULL,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  is_deleted      BOOLEAN NOT NULL DEFAULT false,
  institute_id    TEXT NOT NULL DEFAULT 'default_institute'
);

-- =============================================================================
-- ROW LEVEL SECURITY
-- Dev policy: fully permissive so anon/authenticated upserts from the app
-- succeed. REPLACE with institute-scoped, authenticated policies before
-- production, e.g.:
--   CREATE POLICY "Institute access" ON <table>
--     FOR ALL TO authenticated
--     USING (institute_id = current_setting('request.jwt.claims', true)::json->>'institute_id')
--     WITH CHECK (institute_id = current_setting('request.jwt.claims', true)::json->>'institute_id');
-- =============================================================================

ALTER TABLE departments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Dev Access" ON departments;
CREATE POLICY "Dev Access" ON departments FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE academic_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Dev Access" ON academic_sessions;
CREATE POLICY "Dev Access" ON academic_sessions FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Dev Access" ON users;
CREATE POLICY "Dev Access" ON users FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE classes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Dev Access" ON classes;
CREATE POLICY "Dev Access" ON classes FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE teachers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Dev Access" ON teachers;
CREATE POLICY "Dev Access" ON teachers FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE students ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Dev Access" ON students;
CREATE POLICY "Dev Access" ON students FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE subjects ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Dev Access" ON subjects;
CREATE POLICY "Dev Access" ON subjects FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE attendance_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Dev Access" ON attendance_sessions;
CREATE POLICY "Dev Access" ON attendance_sessions FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE attendance_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Dev Access" ON attendance_records;
CREATE POLICY "Dev Access" ON attendance_records FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Dev Access" ON leave_requests;
CREATE POLICY "Dev Access" ON leave_requests FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE lab_inventory ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Dev Access" ON lab_inventory;
CREATE POLICY "Dev Access" ON lab_inventory FOR ALL USING (true) WITH CHECK (true);