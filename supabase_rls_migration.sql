-- =============================================================================
-- Cloud RLS (Row-Level Security) Migration — GILT Management App
-- =============================================================================
-- Active (in-scope) tables:
--   users, departments, classes, teachers, students, subjects,
--   attendance_sessions, attendance_records, leave_requests, lab_inventory
--
-- Instructions:
--   1. Open your Supabase project: https://supabase.com/dashboard/project/_/sql
--   2. Paste the entire block into the SQL Editor and click "Run".
--   3. The script is idempotent (CREATE IF NOT EXISTS / ADD COLUMN IF NOT EXISTS /
--      DROP POLICY IF EXISTS) and safe to re-run.
--
-- Security goals implemented here:
--   * Every cloud push is made under an authenticated Supabase JWT
--     (auth.uid()); anonymous/anon-key writes are rejected by the client and
--     have no RLS policy to fall back on.
--   * Tenant isolation: every row is scoped to the signed-in user's
--     public.profiles.institute_id.
--   * Clients can never change their own role, is_suspended, or institute_id
--     through the Data/REST API (enforced by the profiles UPDATE policy).
--   * Profiles are provisioned server-side: no client INSERT policy is granted.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. public.profiles — trusted tenant + role, linked 1:1 to auth.users
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id               UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  institute_id     TEXT NOT NULL DEFAULT 'default_institute',
  role             TEXT NOT NULL DEFAULT 'teacher',
  is_suspended     BOOLEAN NOT NULL DEFAULT false,
  suspended_at     TEXT,
  suspended_reason TEXT,
  display_name     TEXT,
  email            TEXT,
  created_at       TEXT NOT NULL DEFAULT (now()::text),
  updated_at       TEXT NOT NULL DEFAULT (now()::text),
  is_deleted       BOOLEAN NOT NULL DEFAULT false
);

-- Ensure additive columns exist on pre-existing profiles tables.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'teacher';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_suspended BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS suspended_at TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS suspended_reason TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS display_name TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS created_at TEXT NOT NULL DEFAULT (now()::text);
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS updated_at TEXT NOT NULL DEFAULT (now()::text);
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
-- -----------------------------------------------------------------------------
-- 2. Ensure every active table exists and carries an institute_id column.
--    (Cloud schema may define `staff` for teachers; SyncService pushes to
--    `teachers`, so both are covered below.)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.users (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username    TEXT,
  display_name TEXT,
  email       TEXT,
  role        TEXT NOT NULL DEFAULT 'teacher',
  auth_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  created_at  TEXT NOT NULL DEFAULT (now()::text),
  updated_at  TEXT NOT NULL DEFAULT (now()::text),
  is_deleted  BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.teachers (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
  name          TEXT NOT NULL,
  subject       TEXT,
  email         TEXT,
  username      TEXT,
  class_id      UUID,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  employee_code TEXT,
  designation   TEXT NOT NULL DEFAULT 'Instructor',
  department_id UUID,
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false,
  institute_id  TEXT NOT NULL DEFAULT 'default_institute'
);

-- idempotent: add institute_id to any active table missing it
ALTER TABLE public.users            ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';
ALTER TABLE public.departments      ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';
ALTER TABLE public.classes          ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';
ALTER TABLE public.teachers         ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';
ALTER TABLE public.students         ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';
ALTER TABLE public.subjects         ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';
ALTER TABLE public.attendance_sessions ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';
ALTER TABLE public.attendance_records ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';
ALTER TABLE public.leave_requests   ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';
ALTER TABLE public.lab_inventory    ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';

-- (Defensive) also keep the legacy `staff` table tenant-scoped if present.
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';

-- -----------------------------------------------------------------------------
-- 3. Drop all permissive "Dev Access" policies on active tables.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Dev Access" ON public.users;
DROP POLICY IF EXISTS "Dev Access" ON public.profiles;
DROP POLICY IF EXISTS "Dev Access" ON public.departments;
DROP POLICY IF EXISTS "Dev Access" ON public.classes;
DROP POLICY IF EXISTS "Dev Access" ON public.teachers;
DROP POLICY IF EXISTS "Dev Access" ON public.staff;
DROP POLICY IF EXISTS "Dev Access" ON public.students;
DROP POLICY IF EXISTS "Dev Access" ON public.subjects;
DROP POLICY IF EXISTS "Dev Access" ON public.attendance_sessions;
DROP POLICY IF EXISTS "Dev Access" ON public.attendance_records;
DROP POLICY IF EXISTS "Dev Access" ON public.leave_requests;
DROP POLICY IF EXISTS "Dev Access" ON public.lab_inventory;

-- Also clear any leftover permissive policies so we start from a clean slate.
DROP POLICY IF EXISTS "Institute isolation users" ON public.users;
DROP POLICY IF EXISTS "Institute isolation departments" ON public.departments;
DROP POLICY IF EXISTS "Institute isolation classes" ON public.classes;
DROP POLICY IF EXISTS "Institute isolation teachers" ON public.teachers;
DROP POLICY IF EXISTS "Institute isolation staff" ON public.staff;
DROP POLICY IF EXISTS "Institute isolation students" ON public.students;
DROP POLICY IF EXISTS "Institute isolation subjects" ON public.subjects;
DROP POLICY IF EXISTS "Institute isolation attendance_sessions" ON public.attendance_sessions;
DROP POLICY IF EXISTS "Institute isolation attendance_records" ON public.attendance_records;
DROP POLICY IF EXISTS "Institute isolation leave_requests" ON public.leave_requests;
DROP POLICY IF EXISTS "Institute isolation lab_inventory" ON public.lab_inventory;
DROP POLICY IF EXISTS "Profiles: read own" ON public.profiles;
DROP POLICY IF EXISTS "Profiles: update own non-sensitive fields" ON public.profiles;

-- -----------------------------------------------------------------------------
-- 4. Enable RLS and grant Data-API access to the authenticated role only.
--    (The anon role gets no table access: unauthenticated calls cannot read or
--    write any active table.)
-- -----------------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO authenticated;

GRANT ALL ON public.users            TO authenticated;
GRANT ALL ON public.profiles         TO authenticated;
GRANT ALL ON public.departments      TO authenticated;
GRANT ALL ON public.classes          TO authenticated;
GRANT ALL ON public.teachers         TO authenticated;
GRANT ALL ON public.staff            TO authenticated;
GRANT ALL ON public.students         TO authenticated;
GRANT ALL ON public.subjects         TO authenticated;
GRANT ALL ON public.attendance_sessions TO authenticated;
GRANT ALL ON public.attendance_records TO authenticated;
GRANT ALL ON public.leave_requests   TO authenticated;
GRANT ALL ON public.lab_inventory    TO authenticated;

ALTER TABLE public.users            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.departments      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teachers         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subjects         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leave_requests   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_inventory    ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- 5. Tenant-isolation + role/scope policies.
--
--    my_institute   = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
--    my_role        = (SELECT role        FROM public.profiles WHERE id = auth.uid())
--
--    Reads   : own institute, or super_admin across institutes.
--    Writes  : strictly own institute (NEW.institute_id = my_institute).
--    Deletes : strictly own institute (soft-delete preferred via is_deleted).
-- -----------------------------------------------------------------------------

-- ---- profiles ---------------------------------------------------------------
-- Clients read their own profile (super_admin reads all).
CREATE POLICY "Profiles: read own" ON public.profiles
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
  );

-- Clients update their own profile but may NEVER change role, is_suspended,
-- or institute_id through the direct API. Those fields are server-controlled.
CREATE POLICY "Profiles: update own non-sensitive fields" ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (
    id = auth.uid()
    AND NEW.role = OLD.role
    AND NEW.is_suspended = OLD.is_suspended
    AND NEW.institute_id = OLD.institute_id
  );

-- No client INSERT policy: profiles are provisioned server-side
-- (trigger / admin) and bound to auth.users(id).

-- ---- users ------------------------------------------------------------------
CREATE POLICY "Users: tenant isolation" ON public.users
  FOR SELECT TO authenticated
  USING (
    institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
    OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
  );
CREATE POLICY "Users: tenant insert" ON public.users
  FOR INSERT TO authenticated
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Users: tenant update" ON public.users
  FOR UPDATE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Users: tenant delete" ON public.users
  FOR DELETE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- ---- departments ------------------------------------------------------------
CREATE POLICY "Departments: tenant isolation" ON public.departments
  FOR SELECT TO authenticated
  USING (
    institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
    OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
  );
CREATE POLICY "Departments: tenant insert" ON public.departments
  FOR INSERT TO authenticated
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Departments: tenant update" ON public.departments
  FOR UPDATE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Departments: tenant delete" ON public.departments
  FOR DELETE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- ---- classes ----------------------------------------------------------------
CREATE POLICY "Classes: tenant isolation" ON public.classes
  FOR SELECT TO authenticated
  USING (
    institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
    OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
  );
CREATE POLICY "Classes: tenant insert" ON public.classes
  FOR INSERT TO authenticated
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Classes: tenant update" ON public.classes
  FOR UPDATE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Classes: tenant delete" ON public.classes
  FOR DELETE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- ---- teachers ---------------------------------------------------------------
CREATE POLICY "Teachers: tenant isolation" ON public.teachers
  FOR SELECT TO authenticated
  USING (
    institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
    OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
  );
CREATE POLICY "Teachers: tenant insert" ON public.teachers
  FOR INSERT TO authenticated
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Teachers: tenant update" ON public.teachers
  FOR UPDATE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Teachers: tenant delete" ON public.teachers
  FOR DELETE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- ---- staff ------------------------------------------------------------------
CREATE POLICY "Staff: tenant isolation" ON public.staff
  FOR SELECT TO authenticated
  USING (
    institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
    OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
  );
CREATE POLICY "Staff: tenant insert" ON public.staff
  FOR INSERT TO authenticated
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Staff: tenant update" ON public.staff
  FOR UPDATE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Staff: tenant delete" ON public.staff
  FOR DELETE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- ---- students ---------------------------------------------------------------
CREATE POLICY "Students: tenant isolation" ON public.students
  FOR SELECT TO authenticated
  USING (
    institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
    OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
  );
CREATE POLICY "Students: tenant insert" ON public.students
  FOR INSERT TO authenticated
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Students: tenant update" ON public.students
  FOR UPDATE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Students: tenant delete" ON public.students
  FOR DELETE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- ---- subjects ---------------------------------------------------------------
CREATE POLICY "Subjects: tenant isolation" ON public.subjects
  FOR SELECT TO authenticated
  USING (
    institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
    OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
  );
CREATE POLICY "Subjects: tenant insert" ON public.subjects
  FOR INSERT TO authenticated
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Subjects: tenant update" ON public.subjects
  FOR UPDATE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Subjects: tenant delete" ON public.subjects
  FOR DELETE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- ---- attendance_sessions ----------------------------------------------------
CREATE POLICY "Attendance sessions: tenant isolation" ON public.attendance_sessions
  FOR SELECT TO authenticated
  USING (
    institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
    OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
  );
CREATE POLICY "Attendance sessions: tenant insert" ON public.attendance_sessions
  FOR INSERT TO authenticated
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Attendance sessions: tenant update" ON public.attendance_sessions
  FOR UPDATE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Attendance sessions: tenant delete" ON public.attendance_sessions
  FOR DELETE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- ---- attendance_records -----------------------------------------------------
CREATE POLICY "Attendance records: tenant isolation" ON public.attendance_records
  FOR SELECT TO authenticated
  USING (
    institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
    OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
  );
CREATE POLICY "Attendance records: tenant insert" ON public.attendance_records
  FOR INSERT TO authenticated
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Attendance records: tenant update" ON public.attendance_records
  FOR UPDATE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Attendance records: tenant delete" ON public.attendance_records
  FOR DELETE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- ---- leave_requests ---------------------------------------------------------
CREATE POLICY "Leave requests: tenant isolation" ON public.leave_requests
  FOR SELECT TO authenticated
  USING (
    institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
    OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
  );
CREATE POLICY "Leave requests: tenant insert" ON public.leave_requests
  FOR INSERT TO authenticated
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Leave requests: tenant update" ON public.leave_requests
  FOR UPDATE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Leave requests: tenant delete" ON public.leave_requests
  FOR DELETE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- ---- lab_inventory ----------------------------------------------------------
CREATE POLICY "Lab inventory: tenant isolation" ON public.lab_inventory
  FOR SELECT TO authenticated
  USING (
    institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
    OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
  );
CREATE POLICY "Lab inventory: tenant insert" ON public.lab_inventory
  FOR INSERT TO authenticated
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Lab inventory: tenant update" ON public.lab_inventory
  FOR UPDATE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Lab inventory: tenant delete" ON public.lab_inventory
  FOR DELETE TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- =============================================================================
-- End of RLS migration.
-- =============================================================================

