-- =============================================================================
-- RBAC & PERMISSION ENGINE MIGRATION (READY-TO-PASTE FOR SUPABASE SQL EDITOR)
-- =============================================================================
-- Instructions:
-- 1. Open your Supabase Dashboard: https://supabase.com/dashboard/project/_/sql
-- 2. Open the SQL Editor and paste this block.
-- 3. Click "Run" to establish or upgrade the RBAC tables, constraints, policies,
--    and seed all 10 predefined roles, permissions, and default grant matrices.
-- =============================================================================

-- 1. ROLES TABLE
CREATE TABLE IF NOT EXISTS public.roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  code TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL DEFAULT '',
  is_custom BOOLEAN NOT NULL DEFAULT false,
  is_institute_wide BOOLEAN NOT NULL DEFAULT false,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  sync_status TEXT NOT NULL DEFAULT 'SYNCED',
  is_deleted BOOLEAN NOT NULL DEFAULT false,
  institute_id TEXT NOT NULL DEFAULT 'default_institute'
);

-- Ensure additive columns exist if table was already created previously
ALTER TABLE public.roles ADD COLUMN IF NOT EXISTS code TEXT;
ALTER TABLE public.roles ADD COLUMN IF NOT EXISTS is_custom BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.roles ADD COLUMN IF NOT EXISTS is_institute_wide BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.roles ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';
ALTER TABLE public.roles ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.roles ADD COLUMN IF NOT EXISTS sync_status TEXT NOT NULL DEFAULT 'SYNCED';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'roles_code_key'
  ) THEN
    ALTER TABLE public.roles ADD CONSTRAINT roles_code_key UNIQUE (code);
  END IF;
END $$;

-- 2. PERMISSIONS TABLE
CREATE TABLE IF NOT EXISTS public.permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL DEFAULT '',
  module TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  sync_status TEXT NOT NULL DEFAULT 'SYNCED',
  is_deleted BOOLEAN NOT NULL DEFAULT false,
  institute_id TEXT NOT NULL DEFAULT 'default_institute'
);

ALTER TABLE public.permissions ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';
ALTER TABLE public.permissions ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.permissions ADD COLUMN IF NOT EXISTS sync_status TEXT NOT NULL DEFAULT 'SYNCED';

-- 3. ROLE_PERMISSIONS TABLE (role_id + permission_code)
CREATE TABLE IF NOT EXISTS public.role_permissions (
  role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  permission_code TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  PRIMARY KEY (role_id, permission_code)
);

ALTER TABLE public.role_permissions ADD COLUMN IF NOT EXISTS permission_code TEXT;

-- 4. USER_ROLES TABLE
CREATE TABLE IF NOT EXISTS public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  assigned_at TEXT DEFAULT (now()::text),
  assigned_by TEXT,
  updated_at TEXT DEFAULT (now()::text),
  sync_status TEXT NOT NULL DEFAULT 'PENDING',
  is_deleted BOOLEAN NOT NULL DEFAULT false,
  UNIQUE (user_id, role_id)
);

ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid();
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS institute_id TEXT NOT NULL DEFAULT 'default_institute';
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS assigned_at TEXT DEFAULT (now()::text);
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS assigned_by TEXT;
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS updated_at TEXT DEFAULT (now()::text);
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS sync_status TEXT NOT NULL DEFAULT 'PENDING';
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;

-- 5. USER_DEPARTMENTS TABLE
CREATE TABLE IF NOT EXISTS public.user_departments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  sync_status TEXT NOT NULL DEFAULT 'PENDING',
  is_deleted BOOLEAN NOT NULL DEFAULT false,
  UNIQUE (user_id, department_id)
);

ALTER TABLE public.user_departments ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid();
ALTER TABLE public.user_departments ADD COLUMN IF NOT EXISTS created_at TEXT NOT NULL DEFAULT (now()::text);
ALTER TABLE public.user_departments ADD COLUMN IF NOT EXISTS sync_status TEXT NOT NULL DEFAULT 'PENDING';
ALTER TABLE public.user_departments ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;

-- 6. SUPPORTING INDEXES
CREATE INDEX IF NOT EXISTS idx_roles_code ON public.roles(code);
CREATE INDEX IF NOT EXISTS idx_permissions_code ON public.permissions(code);
CREATE INDEX IF NOT EXISTS idx_role_permissions_role_id ON public.role_permissions(role_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON public.user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role_id ON public.user_roles(role_id);
CREATE INDEX IF NOT EXISTS idx_user_departments_user_id ON public.user_departments(user_id);

-- 7. ENABLE ROW-LEVEL SECURITY (RLS)
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_departments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow authenticated read roles" ON public.roles;
CREATE POLICY "Allow authenticated read roles" ON public.roles FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow authenticated write roles" ON public.roles;
CREATE POLICY "Allow authenticated write roles" ON public.roles FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated read permissions" ON public.permissions;
CREATE POLICY "Allow authenticated read permissions" ON public.permissions FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow authenticated write permissions" ON public.permissions;
CREATE POLICY "Allow authenticated write permissions" ON public.permissions FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated read role_permissions" ON public.role_permissions;
CREATE POLICY "Allow authenticated read role_permissions" ON public.role_permissions FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow authenticated write role_permissions" ON public.role_permissions;
CREATE POLICY "Allow authenticated write role_permissions" ON public.role_permissions FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated read user_roles" ON public.user_roles;
CREATE POLICY "Allow authenticated read user_roles" ON public.user_roles FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow authenticated write user_roles" ON public.user_roles;
CREATE POLICY "Allow authenticated write user_roles" ON public.user_roles FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated read user_departments" ON public.user_departments;
CREATE POLICY "Allow authenticated read user_departments" ON public.user_departments FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow authenticated write user_departments" ON public.user_departments;
CREATE POLICY "Allow authenticated write user_departments" ON public.user_departments FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 8. SEED CANONICAL PERMISSIONS
INSERT INTO public.permissions (code, module, description) VALUES
  ('student.view', 'students', 'View student records'),
  ('student.create', 'students', 'Create new students'),
  ('student.edit', 'students', 'Edit student records'),
  ('student.delete', 'students', 'Delete students'),
  ('teacher.view', 'teachers', 'View teacher records'),
  ('teacher.create', 'teachers', 'Create teachers'),
  ('teacher.edit', 'teachers', 'Edit teachers'),
  ('teacher.delete', 'teachers', 'Delete teachers'),
  ('attendance.view', 'attendance', 'View attendance'),
  ('attendance.mark', 'attendance', 'Mark attendance'),
  ('attendance.edit', 'attendance', 'Edit attendance'),
  ('attendance.delete', 'attendance', 'Delete attendance'),
  ('attendance.correct_after_deadline', 'attendance', 'Correct attendance after deadline'),
  ('leave.view', 'leave', 'View leave requests'),
  ('leave.approve', 'leave', 'Approve or reject leave'),
  ('user.view', 'users', 'View users'),
  ('user.create', 'users', 'Create users'),
  ('user.edit', 'users', 'Edit users'),
  ('user.delete', 'users', 'Delete users'),
  ('user.manage_roles', 'users', 'Manage user roles (Admin / Principal / VP)'),
  ('class.manage', 'classes', 'Manage classes'),
  ('report.view', 'reports', 'View reports'),
  ('fee.view', 'fees', 'View fees'),
  ('fee.manage', 'fees', 'Manage fees'),
  ('lab.view', 'lab', 'View lab inventory'),
  ('lab.manage', 'lab', 'Manage lab inventory'),
  ('setting.manage', 'settings', 'Manage settings'),
  ('dashboard.view', 'dashboard', 'View dashboard')
ON CONFLICT (code) DO UPDATE SET
  module = EXCLUDED.module,
  description = EXCLUDED.description;

-- 9. SEED PREDEFINED ROLES
INSERT INTO public.roles (name, code, description, is_institute_wide, is_custom) VALUES
  ('Administrator', 'admin', 'Full system access including user and role management.', true, false),
  ('Principal', 'principal', 'Institute-wide academic authority.', true, false),
  ('Vice Principal', 'vice_principal', 'Institute-wide academic authority.', true, false),
  ('Head of Department', 'hod', 'Department-scoped academic authority (default grant scope).', false, false),
  ('Teacher', 'teacher', 'Classroom instruction and attendance for own classes.', false, false),
  ('Student', 'student', 'Own records only.', false, false),
  ('Parent', 'parent', 'Child''s records only.', false, false),
  ('Accountant', 'accountant', 'Fees and payments.', false, false),
  ('Lab In-Charge', 'lab_in_charge', 'Lab inventory.', false, false),
  ('Assistant', 'assistant', 'Limited administrative support.', false, false)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  is_institute_wide = EXCLUDED.is_institute_wide;

-- 10. SEED DEFAULT ROLE-PERMISSION GRANTS
-- Institute-wide roles: admin, principal, vice_principal get all permissions
INSERT INTO public.role_permissions (role_id, permission_code)
SELECT r.id, p.code
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.code IN ('admin', 'principal', 'vice_principal')
ON CONFLICT (role_id, permission_code) DO NOTHING;

-- HOD grants
INSERT INTO public.role_permissions (role_id, permission_code)
SELECT r.id, p_code
FROM public.roles r,
(VALUES
  ('student.view'),
  ('student.edit'),
  ('teacher.view'),
  ('attendance.view'),
  ('attendance.mark'),
  ('attendance.edit'),
  ('leave.view'),
  ('leave.approve'),
  ('report.view'),
  ('class.manage')
) AS perms(p_code)
WHERE r.code = 'hod'
ON CONFLICT (role_id, permission_code) DO NOTHING;

-- Teacher grants
INSERT INTO public.role_permissions (role_id, permission_code)
SELECT r.id, p_code
FROM public.roles r,
(VALUES
  ('attendance.view'),
  ('attendance.mark'),
  ('student.view'),
  ('leave.view')
) AS perms(p_code)
WHERE r.code = 'teacher'
ON CONFLICT (role_id, permission_code) DO NOTHING;

-- Student grants
INSERT INTO public.role_permissions (role_id, permission_code)
SELECT r.id, p_code
FROM public.roles r,
(VALUES
  ('attendance.view'),
  ('leave.view'),
  ('dashboard.view')
) AS perms(p_code)
WHERE r.code = 'student'
ON CONFLICT (role_id, permission_code) DO NOTHING;

-- Parent grants
INSERT INTO public.role_permissions (role_id, permission_code)
SELECT r.id, p_code
FROM public.roles r,
(VALUES
  ('attendance.view'),
  ('leave.view'),
  ('dashboard.view')
) AS perms(p_code)
WHERE r.code = 'parent'
ON CONFLICT (role_id, permission_code) DO NOTHING;

-- Accountant grants
INSERT INTO public.role_permissions (role_id, permission_code)
SELECT r.id, p_code
FROM public.roles r,
(VALUES
  ('fee.view'),
  ('fee.manage'),
  ('report.view')
) AS perms(p_code)
WHERE r.code = 'accountant'
ON CONFLICT (role_id, permission_code) DO NOTHING;

-- Lab In-Charge grants
INSERT INTO public.role_permissions (role_id, permission_code)
SELECT r.id, p_code
FROM public.roles r,
(VALUES
  ('lab.view'),
  ('lab.manage')
) AS perms(p_code)
WHERE r.code = 'lab_in_charge'
ON CONFLICT (role_id, permission_code) DO NOTHING;

-- Assistant grants
INSERT INTO public.role_permissions (role_id, permission_code)
SELECT r.id, p_code
FROM public.roles r,
(VALUES
  ('student.view'),
  ('attendance.view'),
  ('dashboard.view')
) AS perms(p_code)
WHERE r.code = 'assistant'
ON CONFLICT (role_id, permission_code) DO NOTHING;

-- =============================================================================
-- END OF RBAC MIGRATION SCRIPT
-- =============================================================================


-- supabase_schema.sql â€” Cloud schema for the GILT Management App
-- =============================================================================

-- 0. profiles
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  role TEXT NOT NULL DEFAULT 'admin',
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 1. roles
CREATE TABLE IF NOT EXISTS public.roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL DEFAULT '',
  is_custom BOOLEAN NOT NULL DEFAULT false,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 2. permissions
CREATE TABLE IF NOT EXISTS public.permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL DEFAULT '',
  module TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 3. role_permissions
CREATE TABLE IF NOT EXISTS public.role_permissions (
  role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

-- 4. user_departments
CREATE TABLE IF NOT EXISTS public.user_departments (
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, department_id)
);

-- 5. user_roles
CREATE TABLE IF NOT EXISTS public.user_roles (
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);
-- 6. departments
CREATE TABLE IF NOT EXISTS public.departments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  code TEXT,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 7. academic_sessions
CREATE TABLE IF NOT EXISTS public.academic_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  is_current BOOLEAN NOT NULL DEFAULT false,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 8. classes
CREATE TABLE IF NOT EXISTS public.classes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  code TEXT,
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 9. subjects
CREATE TABLE IF NOT EXISTS public.subjects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  code TEXT,
  class_id UUID REFERENCES public.classes(id) ON DELETE SET NULL,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 10. staff
CREATE TABLE IF NOT EXISTS public.staff (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  employee_id TEXT NOT NULL UNIQUE,
  designation TEXT,
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
-- 12. parents
CREATE TABLE IF NOT EXISTS public.parents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 13. attendance_sessions
CREATE TABLE IF NOT EXISTS public.attendance_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  subject_id UUID,
  date TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  correction_deadline TEXT,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 14. attendance_records
CREATE TABLE IF NOT EXISTS public.attendance_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'present',
  marked_at TEXT DEFAULT (now()::text),
  corrected_at TEXT,
  notes TEXT,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 15. exam_results
CREATE TABLE IF NOT EXISTS public.exam_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  subject_id UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  marks INTEGER NOT NULL,
  is_published BOOLEAN NOT NULL DEFAULT false,
  edit_approved_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 16. fee_records
CREATE TABLE IF NOT EXISTS public.fee_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  fee_structure_id UUID,
  status TEXT NOT NULL DEFAULT 'unpaid' CHECK (status IN ('paid', 'unpaid', 'partial')),
  amount_paid INTEGER NOT NULL DEFAULT 0,
  amount_total INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  is_deleted BOOLEAN NOT NULL DEFAULT false
);
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 11. students
CREATE TABLE IF NOT EXISTS public.students (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  roll_no TEXT NOT NULL,
  class_id UUID REFERENCES public.classes(id) ON DELETE SET NULL,
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_active BOOLEAN NOT NULL DEFAULT true,
  is_deleted BOOLEAN NOT NULL DEFAULT false
);
-- supabase_schema.sql â€” Cloud schema for the GILT Management App
-- =============================================================================

-- 0. profiles
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  role TEXT NOT NULL DEFAULT 'admin',
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 1. roles
CREATE TABLE IF NOT EXISTS public.roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL DEFAULT '',
  is_custom BOOLEAN NOT NULL DEFAULT false,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 2. permissions
CREATE TABLE IF NOT EXISTS public.permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL DEFAULT '',
  module TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 3. role_permissions
CREATE TABLE IF NOT EXISTS public.role_permissions (
  role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

-- 4. user_departments
CREATE TABLE IF NOT EXISTS public.user_departments (
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, department_id)
);

-- 5. user_roles
CREATE TABLE IF NOT EXISTS public.user_roles (
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);
-- supabase_schema.sql â€” Cloud schema for the GILT Management App
-- =============================================================================

-- 0. profiles
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  role TEXT NOT NULL DEFAULT 'admin',
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 1. roles
CREATE TABLE IF NOT EXISTS public.roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL DEFAULT '',
  is_custom BOOLEAN NOT NULL DEFAULT false,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 2. permissions
CREATE TABLE IF NOT EXISTS public.permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL DEFAULT '',
  module TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 3. role_permissions
CREATE TABLE IF NOT EXISTS public.role_permissions (
  role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

-- 4. user_departments
CREATE TABLE IF NOT EXISTS public.user_departments (
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, department_id)
);

-- 5. user_roles
CREATE TABLE IF NOT EXISTS public.user_roles (
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);
-- =============================================================================
-- supabase_schema.sql â€” Cloud schema for the GILT Management App
-- =============================================================================

-- TYPE MAPPING (payload value -> column type):
--   id                canonical UUID string      -> id UUID PRIMARY KEY
--   Dart bool         JSON true/false            -> BOOLEAN
--   Dart double       JSON number                -> DOUBLE PRECISION
--   Dart int          JSON number                -> INTEGER
--   Dart DateTime     ISO-8601 string            -> TEXT (kept as TEXT so
--                      PostgREST upserts can never fail a timestamp cast;
--                      switch to TIMESTAMPTZ later if you want server-side
--                      time handling â€” values are already ISO-8601)

-- DELIBERATELY EXCLUDED (local-only, never sent over the wire):
--   sync_status, is_synced, password, password_hash, legacy alias columns
--   (roll_no, full_name), JOIN-only display fields

-- Safe to re-run: CREATE TABLE IF NOT EXISTS + DROP POLICY IF EXISTS.
-- Paste this entire file into the Supabase SQL Editor and run it once.
-- =============================================================================

-- 0. public.profiles  (server-controlled tenant identity)
-- ---------------------------------------------------------
-- Linked 1:1 to Supabase Auth users. `institute_id` and `role` are trusted,
-- server-controlled fields: clients can read their own row but must never be
-- able to change `institute_id` or `role` (see the RLS policies below).
-- Profiles are provisioned server-side; no client INSERT policy is granted.
CREATE TABLE IF NOT EXISTS public.profiles (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  institute_id  TEXT NOT NULL DEFAULT 'default_institute',
  role          TEXT NOT NULL DEFAULT 'admin',
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false
);

-- -----------------------------------------------------------------------------
-- 1. roles  (Role.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.roles (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL UNIQUE,
  description   TEXT NOT NULL DEFAULT '',
  is_custom     BOOLEAN NOT NULL DEFAULT false,
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false
);

-- -----------------------------------------------------------------------------
-- 2. permissions  (Permission.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.permissions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code          TEXT NOT NULL UNIQUE,
  description   TEXT NOT NULL DEFAULT '',
  module        TEXT NOT NULL,
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false
);

-- -----------------------------------------------------------------------------
-- 3. role_permissions  (junction table)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.role_permissions (
  role_id       UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

-- -----------------------------------------------------------------------------
-- 4. user_departments  (junction table)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_departments (
  user_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, department_id)
);

-- -----------------------------------------------------------------------------
-- 5. user_roles  (junction table)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_roles (
  user_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role_id       UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);
-- =============================================================================
-- supabase_schema.sql â€” Cloud schema for the GILT Management App
-- =============================================================================

-- TYPE MAPPING (payload value -> column type):
--   id                canonical UUID string      -> id UUID PRIMARY KEY
--   Dart bool         JSON true/false            -> BOOLEAN
--   Dart double       JSON number                -> DOUBLE PRECISION
--   Dart int          JSON number                -> INTEGER
--   Dart DateTime     ISO-8601 string            -> TEXT (kept as TEXT so
--                      PostgREST upserts can never fail a timestamp cast;
--                      switch to TIMESTAMPTZ later if you want server-side
--                      time handling â€” values are already ISO-8601)

-- DELIBERATELY EXCLUDED (local-only, never sent over the wire):
--   sync_status, is_synced, password, password_hash, legacy alias columns
--   (roll_no, full_name), JOIN-only display fields

-- Safe to re-run: CREATE TABLE IF NOT EXISTS + DROP POLICY IF EXISTS.
-- Paste this entire file into the Supabase SQL Editor and run it once.
-- =============================================================================

-- 0. public.profiles  (server-controlled tenant identity)
-- ---------------------------------------------------------
-- Linked 1:1 to Supabase Auth users. `institute_id` and `role` are trusted,
-- server-controlled fields: clients can read their own row but must never be
-- able to change `institute_id` or `role` (see the RLS policies below).
-- Profiles are provisioned server-side; no client INSERT policy is granted.
CREATE TABLE IF NOT EXISTS public.profiles (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  institute_id  TEXT NOT NULL DEFAULT 'default_institute',
  role          TEXT NOT NULL DEFAULT 'admin',
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false
);

-- -----------------------------------------------------------------------------
-- 1. roles  (Role.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.roles (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL UNIQUE,
  description   TEXT NOT NULL DEFAULT '',
  is_custom     BOOLEAN NOT NULL DEFAULT false,
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false
);

-- -----------------------------------------------------------------------------
-- 2. permissions  (Permission.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.permissions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code          TEXT NOT NULL UNIQUE,
  description   TEXT NOT NULL DEFAULT '',
  module        TEXT NOT NULL,
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false
);

-- -----------------------------------------------------------------------------
-- 3. role_permissions  (junction table)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.role_permissions (
  role_id       UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

-- 4. user_departments  (junction table)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_departments (
  user_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, department_id)
);

-- 5. user_roles  (junction table)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_roles (
  user_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role_id       UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);
-- -----------------------------------------------------------------------------
-- 4. user_departments  (junction table)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_departments (
  user_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, department_id)
);

-- 5. user_roles  (junction table)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_roles (
  user_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role_id       UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);

-- -----------------------------------------------------------------------------
-- 5. user_departments
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_departments (
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  department_id UUID NOT NULL,
  PRIMARY KEY (user_id, department_id)
);
-- -----------------------------------------------------------------------------
-- 12. attendance_sessions
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.attendance_sessions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id      UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  subject_id    UUID REFERENCES public.subjects(id) ON DELETE SET NULL,
  date          TEXT NOT NULL,
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  correction_deadline TEXT,
-- -----------------------------------------------------------------------------
-- 14. exam_results
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.exam_results (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id    UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  subject_id    UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  marks         INTEGER NOT NULL,
  is_published  BOOLEAN NOT NULL DEFAULT false,
  edit_approved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false
);

-- -----------------------------------------------------------------------------
-- 15. fee_records
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fee_records (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id    UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  fee_structure_id UUID,
  status        TEXT NOT NULL DEFAULT 'unpaid' CHECK (status IN ('paid', 'unpaid', 'partial')),
  amount_paid   INTEGER NOT NULL DEFAULT 0,
  amount_total  INTEGER NOT NULL,
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false
);
  institute_id  TEXT NOT NULL DEFAULT 'default_institute'
);

-- -----------------------------------------------------------------------------
-- 13. attendance_records
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.attendance_records (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id    UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
  student_id    UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  status        TEXT NOT NULL DEFAULT 'present',
  marked_at     TEXT DEFAULT (now()::text),
  corrected_at  TEXT,
  notes         TEXT,
  institute_id  TEXT NOT NULL DEFAULT 'default_institute'
);
-- -----------------------------------------------------------------------------
-- 6. departments
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.departments (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  code          TEXT NOT NULL UNIQUE,
  description   TEXT NOT NULL DEFAULT '',
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false
);

-- -----------------------------------------------------------------------------
-- 7. staff  (Staff.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id   TEXT NOT NULL UNIQUE,
  designation   TEXT,
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false
);

-- -----------------------------------------------------------------------------
-- 8. students  (Student.toSupabaseJson)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.students (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  roll_no       TEXT NOT NULL,
  class_id      UUID REFERENCES public.classes(id) ON DELETE SET NULL,
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false
);

-- -----------------------------------------------------------------------------
-- 9. parents  (linked to verified student)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.parents (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  student_id    UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false
);

-- -----------------------------------------------------------------------------
-- 10. classes
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.classes (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  year_level    TEXT,
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  code          TEXT,
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false
);

-- -----------------------------------------------------------------------------
-- 11. subjects
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.subjects (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  code          TEXT,
  class_id      UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  created_at    TEXT NOT NULL DEFAULT (now()::text),
  updated_at    TEXT NOT NULL DEFAULT (now()::text),
  is_deleted    BOOLEAN NOT NULL DEFAULT false
);
-- -----------------------------------------------------------------------------
-- Row Level Security Policies
-- -----------------------------------------------------------------------------
-- Enable RLS on all tables
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff ENABLE ROW LEVEL SECURITY;
-- Roles policies
DROP POLICY IF EXISTS "Dev Access" ON public.roles;
CREATE POLICY "Institute isolation roles" ON public.roles
  FOR ALL TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin');

-- Permissions policies
DROP POLICY IF EXISTS "Dev Access" ON public.permissions;
CREATE POLICY "Institute isolation permissions" ON public.permissions
  FOR ALL TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin');

-- Role permissions policies
DROP POLICY IF EXISTS "Dev Access" ON public.role_permissions;
CREATE POLICY "Institute isolation role_permissions" ON public.role_permissions
  FOR ALL TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
-- User roles policies
DROP POLICY IF EXISTS "Dev Access" ON public.user_roles;
CREATE POLICY "Institute isolation user_roles" ON public.user_roles
  FOR ALL TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin');

-- User departments policies
DROP POLICY IF EXISTS "Dev Access" ON public.user_departments;
CREATE POLICY "Institute isolation user_departments" ON public.user_departments
  FOR ALL TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin');

-- Staff policies
DROP POLICY IF EXISTS "Dev Access" ON public.staff;
-- Students policies
DROP POLICY IF EXISTS "Dev Access" ON public.students;
CREATE POLICY "Institute isolation students" ON public.students
  FOR ALL TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- Parents policies
DROP POLICY IF EXISTS "Dev Access" ON public.parents;
CREATE POLICY "Institute isolation parents" ON public.parents
  FOR ALL TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- Classes policies
DROP POLICY IF EXISTS "Dev Access" ON public.classes;
CREATE POLICY "Institute isolation classes" ON public.classes
  FOR ALL TO authenticated
-- Attendance sessions policies
DROP POLICY IF EXISTS "Dev Access" ON public.attendance_sessions;
CREATE POLICY "Institute isolation attendance_sessions" ON public.attendance_sessions
  FOR ALL TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- Attendance records policies
DROP POLICY IF EXISTS "Dev Access" ON public.attendance_records;
CREATE POLICY "Institute isolation attendance_records" ON public.attendance_records
  FOR ALL TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- Exam results policies
DROP POLICY IF EXISTS "Dev Access" ON public.exam_results;
CREATE POLICY "Institute isolation exam_results" ON public.exam_results
  FOR ALL TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- Fee records policies
DROP POLICY IF EXISTS "Dev Access" ON public.fee_records;
CREATE POLICY "Institute isolation fee_records" ON public.fee_records
  FOR ALL TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- Subjects policies
DROP POLICY IF EXISTS "Dev Access" ON public.subjects;
CREATE POLICY "Institute isolation subjects" ON public.subjects
  FOR ALL TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
CREATE POLICY "Institute isolation staff" ON public.staff
  FOR ALL TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));

-- Departments policies
DROP POLICY IF EXISTS "Dev Access" ON public.departments;
CREATE POLICY "Institute isolation departments" ON public.departments
  FOR ALL TO authenticated
  USING (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid())
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin')
  WITH CHECK (institute_id = (SELECT institute_id FROM public.profiles WHERE id = auth.uid()));
     OR (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin');
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parents ENABLE ROW LEVEL SECURITY;

-- 12. parents
CREATE TABLE IF NOT EXISTS public.parents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 13. attendance_sessions
CREATE TABLE IF NOT EXISTS public.attendance_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  subject_id UUID,
  date TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  correction_deadline TEXT,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 14. attendance_records
CREATE TABLE IF NOT EXISTS public.attendance_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'present',
  marked_at TEXT DEFAULT (now()::text),
  corrected_at TEXT,
  notes TEXT,
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 15. exam_results
CREATE TABLE IF NOT EXISTS public.exam_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  subject_id UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  marks INTEGER NOT NULL,
  is_published BOOLEAN NOT NULL DEFAULT false,
  edit_approved_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- 16. fee_records
CREATE TABLE IF NOT EXISTS public.fee_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  fee_structure_id UUID,
  status TEXT NOT NULL DEFAULT 'unpaid' CHECK (status IN ('paid', 'unpaid', 'partial')),
  amount_paid INTEGER NOT NULL DEFAULT 0,
  amount_total INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  institute_id TEXT NOT NULL DEFAULT 'default_institute',
  is_deleted BOOLEAN NOT NULL DEFAULT false
);
-- -----------------------------------------------------------------------------
-- 17. Auth engine migration (append-only, safe to re-run)
-- -----------------------------------------------------------------------------
-- Keeps the cloud `public.profiles` table in parity with the local
-- authentication engine (suspension / lockout / alternate identifiers). The
-- client-side OTP recovery flow is SQLite-only; this table mirrors the code
-- metadata in the cloud for audit / admin tooling.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS roll_no TEXT,
  ADD COLUMN IF NOT EXISTS employee_id TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS is_suspended BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS suspended_reason TEXT,
  ADD COLUMN IF NOT EXISTS failed_login_attempts INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS password_changed_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_profiles_employee_id
  ON public.profiles(employee_id);
CREATE INDEX IF NOT EXISTS idx_profiles_roll_no
  ON public.profiles(roll_no);

CREATE TABLE IF NOT EXISTS public.password_reset_codes (
  email TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  used_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.password_reset_codes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own password reset codes" ON public.password_reset_codes
  FOR ALL TO authenticated
  USING (email = (SELECT email FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (email = (SELECT email FROM public.profiles WHERE id = auth.uid()));
