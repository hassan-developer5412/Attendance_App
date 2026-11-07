# GILT Management App — Authentication & Authorization Audit Report

**App:** GILT Institute Management (Flutter, offline-first, SQLite + Supabase/PostgreSync)  
**Workspace:** `d:\Attendance_APP\FlutterProject`  
**Status:** Audit only — no application files were modified, no database operations performed, no migrations created.  
**Classification:** Internal security audit — contains no secrets, passwords, or access tokens.

---

## 0. Executive Summary

The app is a functional offline-first attendance/institute manager with a local SQLite source of truth and best-effort one-way push synchronization to Supabase. **Authentication works locally, but authorization effectively does not exist**: once a user logs in, every dashboard module is available to every role, the local `role` column is stored but never consulted by the UI, and Supabase Row Level Security is deliberately permissive ("Dev Access: USING true, WITH CHECK true"). The cloud integration is unauthenticated at the data layer (anon key, no JWT claims, no link between Supabase Auth users and local app users).

Against the approved Authentication and Authorization Specification (predefined roles, customizable permissions, custom roles, departmental scope, assigned-class scope, record-level restrictions, attendance correction windows, locked published marks, payment-status visibility, student/parent accounts, offline operation with authorized sync), the current implementation covers almost none of the requirements. The primary architectural issue is that **all authorization is client-side and all trust is local** — a user with file-system access to the device, or a compromised local database, has complete access to all data and can push changes to the cloud under the default institute id because RLS allows it.


## 1. Current Architecture and Authentication Flow

### 1.1 High-level architecture (verified)

- **Persistence:** SQLite via `sqflite`, managed by `DatabaseHelper` singleton (`lib/core/database/database_helper.dart`). Schema version 6, all primary keys are client-generated UUIDs (`lib/core/utils/uuid_utils.dart`).
- **State management:** `provider` (`ChangeNotifier` stores): `AuthStore`, `InstituteStore`, `AttendanceStore`, `LeaveStore`, `ThemeNotifier`.
- **Cloud:** `supabase_flutter` 2.18.0/2.18.3, initialized in `main()` only when `SUPABASE_URL`/`SUPABASE_ANON_KEY` are configured; failures are swallowed and the app runs fully offline (`main.dart:26-38`).
- **Sync:** `SyncService` singleton (`lib/core/services/sync_service.dart`) pushes queued local changes to Supabase every 60 seconds; there is **no pull/download of remote changes**.

### 1.2 User creation (verified)

- **Seeded default admin:** On first launch, `FreshDatabaseCreator.createAndSeed` inserts a `users` row with username `admin`, SHA-256 hash of `Admin@123`, role `admin`, email `admin@institute.edu` (`fresh_database_creator.dart:264-281`). This credential is **hardcoded** in `app_constants.dart:31-34`.
- **Teacher accounts:** `FacultyRepository.insert` creates rows in the `teachers` table with a separate plaintext `password` column and its own `username` — a **parallel credential store** unlinked from `users` (`faculty_repository.dart:35-82`).
- **Cloud accounts:** `AuthStore.signUp` calls `Supabase.instance.client.auth.signUp` (best-effort, returns false if Supabase not ready). There is **no code path** that creates a local `users` row from a Supabase Auth sign-up, and no link between a cloud `auth.users` identity and a local `users.id` (`auth_store.dart:92-109`).
- **Students/parents:** No student or parent user-account creation exists. `students` table holds demographic data only; there is no `parents`/`guardians` table and no student-login flow (`student_repository.dart`, `instute_models.dart`).

### 1.3 Credential storage and verification (verified)

| Item | Detail | File |
|------|--------|------|
| Password hash algorithm | SHA-256, **unsalted**, single iteration | `auth_store.dart:66`, `user_repository.dart:24-34`, `fresh_database_creator.dart:265-267` |
| Where credentials live | `users.password_hash` (local SQLite); `teachers.password` **plaintext** | `database_helper.dart` v6 schema; `faculty_repository.dart:57` |
| Verification query | `SELECT * FROM users WHERE username = ? AND password_hash = ? AND is_deleted = 0 LIMIT 1` | `user_repository.dart:24-34` |
| SharedPreferences | `pref_user_id`, `pref_user_role`, `pref_institute_id` stored **plaintext** | `auth_store.dart:76-84`, `app_constants.dart:10-11,41` |
| Remember-me | UI checkbox `_rememberMe` is **not persisted or used** | `login_screen.dart:23,329-348` |
| Default credentials pre-filled | Login form pre-populated with `admin` / `Admin@123`; "Forgot password?" snackbar reveals them | `login_screen.dart:31-35,51-60,351-363` |

### 1.4 Login flow (verified)

`AuthStore.login(username, password)` (`auth_store.dart:65-88`):

1. `sha256(password)` computed locally.
2. `_userRepository.authenticate(username, hash)` queries local SQLite only.
3. If found → `_currentUser` set, best-effort `_signInToSupabase(user, password)` (Supabase password sign-in using `user.email`; **all failures swallowed**).
4. `pref_user_id` and `pref_user_role` written to SharedPreferences.

### 1.5 Local and cloud identity linking (verified)

**Not linked.** The local `users` row and any Supabase Auth account are independent:

- `_signInToSupabase` signs in with `user.email` + the raw password typed at login. If the email does not exist in Supabase Auth, sign-in fails and is silently ignored — local session still created.
- `SupabaseConfig.instituteId` is adopted from cloud user metadata (`auth_store.dart:146-149`) but no `auth.users.id → local users.id` mapping is ever stored.
- `sync_service.dart` stamps `institute_id` (a mutable static string) on every payload, not a per-user JWT claim.

### 1.6 Supabase Auth usage (verified)

- `main.dart`: `Supabase.initialize(url, publishableKey)` using `--dart-define` or **hardcoded fallback credentials** in `supabase_config.dart:18-19` (the fallback anon key is embedded in source; see §5).
- `auth_store.dart`: `signUp` (sign-up only), `login` → `signInWithPassword` (best-effort), `logout` → `signOut` (best-effort).
- `sync_service.dart`: all Supabase calls use the **anon key client**; no service-role key, no JWT, no per-user authorization context.
- `SupabaseConfig.isReady` gates everything: `isConfigured && isInitialized` (`supabase_config.dart:35`). When not ready, sync is a no-op and local login works offline by design.

### 1.7 Logout and session restoration (verified)

- **Logout:** `AuthStore.logout` — best-effort Supabase `signOut`, then clears `_currentUser`, removes `pref_user_id`/`pref_user_role` from SharedPreferences, notifies (`auth_store.dart:112-127`). `DashboardShell._confirmLogout` triggers it (`dashboard_shell.dart:68-93`).
- **Session restoration:** `AuthStore.init()` reads `pref_user_id` from SharedPreferences, loads the user via `userRepository.getById` (`user_repository.dart:12-22`), sets `_currentUser`, notifies (**no password re-check, no expiry check, no cloud token validation**) (`auth_store.dart:40-57`).
- `main.dart` calls `authStore.init()` during startup before showing `LoginScreen`; if a session exists, `isLoggedIn` is true immediately but `LoginScreen` is still the initial route and `DashboardShell` shows the user's name in the drawer (`dashboard_shell.dart` build).

### 1.8 Can a local session provide access without a valid cloud identity? (verified)

## 2. Verified Findings with File Paths

### 2.1 Authentication findings

| # | Finding | Evidence | Verified / Assumption |
|---|---------|----------|----------------------|
| A1 | Local auth is SHA-256 unsalted against SQLite `users.password_hash` | `user_repository.dart:24-34`, `auth_store.dart:66` | Verified |
| A2 | Default admin `admin`/`Admin@123` hardcoded and seeded on first launch | `app_constants.dart:31-34`, `fresh_database_creator.dart:264-281` | Verified |
| A3 | Default credentials pre-filled in login UI and revealed by "Forgot password?" | `login_screen.dart:31-35,351-363` | Verified |
| A4 | Supabase sign-in is best-effort; failure never blocks local session | `auth_store.dart:73-74,135-153` | Verified |
| A5 | Session restored from SharedPreferences without re-authentication or expiry | `auth_store.dart:40-57` | Verified |
| A6 | `pref_user_role` persisted but never read for authorization anywhere in the UI | `currentUser` used only for display name/email in `settings_content.dart:26-27,88` and `leave_content.dart:37` | Verified |

### 2.2 Database findings

| # | Finding | Evidence |
|---|---------|----------|
| B1 | `users` table: id TEXT PK, username UNIQUE, password_hash, display_name, email, role TEXT DEFAULT 'admin', institute_id, is_synced, sync_status, is_deleted | `fresh_database_creator.dart:56-71` |
| B2 | `teachers` table: separate staff directory with `username`, `password` (plaintext), `employee_code`, `designation`, `department_id`, `class_id`, `is_active` | `fresh_database_creator.dart` (classes/teachers section), `faculty_repository.dart:51-67` |
| B3 | `students` table: name, roll_number, class_id, father_name, department_id, academic_session_id, current_year, status, is_active — **no parent/guardian link** | `fresh_database_creator.dart`, `student_repository.dart:58-105` |
| B4 | No `parents`/`guardians` table, no student↔parent linkage | Absence confirmed across schema/migrations/models |
| B5 | No examinations/results table; no "published marks" lock | Absence confirmed |
| B6 | No fees/financial records table; no payment status | Absence confirmed |
| B7 | No permissions table, no roles table, no custom-roles support, no user-department assignment, no assigned-class scope | Absence confirmed |
| B8 | Every synced table carries `institute_id TEXT` (default `default_institute`) and `is_synced INTEGER` | `fresh_database_creator.dart`, `schema_migration_v5.dart` |
| B9 | `attendance_records`: session_id, student_id, date, status, check_in/out times; UNIQUE(session_id, student_id); no correction window, no locked/published flag, no auditor fields | `fresh_database_creator.dart:189-208` |

### 2.3 Supabase and synchronization findings

| # | Finding | Evidence |
|---|---------|----------|
| C1 | 11 tables replicated: departments, academic_sessions, users, classes, teachers, students, subjects, attendance_sessions, attendance_records, leave_requests, lab_inventory | `sync_service.dart:47-59,63-79`, `schema_migration_v5.dart:22-34` |
| C2 | Sync is **push-only** (local → cloud). No download/pull of remote changes, no conflict detection beyond `updated_at` CAS on mark-synced | `sync_service.dart` (no `select` from Supabase anywhere) |
| C3 | `sync_queue` table: id, entity_type, entity_id, operation, payload JSON, created_at, retry_count, last_error | `fresh_database_creator.dart:249-260`, `sync_queue_item.dart` |
| C4 | Enqueue trigger: any write marks `sync_status='PENDING'`, `is_synced=0`; repositories call `SyncService.instance.schedulePush(...)` | e.g. `user_repository.dart:55`, `student_repository.dart:92` |
| C5 | Background flush every 60s: `_enqueueUnsyncedRows` scans `is_synced = 0 OR sync_status = 'PENDING'`, then `_drainQueue` upserts each item | `sync_service.dart:284-352` |
| C6 | Upsert payload stamped with `SupabaseConfig.instituteId` (mutable static, shared by all users) | `sync_service.dart:254-262` |
| C7 | `_markSynced` uses optimistic CAS (`updated_at = ?`); on mismatch row stays unsynced and is retried next cycle | `sync_service.dart:264-282` |
| C8 | Failed items: `retry_count` incremented, `last_error` stored; **no max-retry limit, no dead-letter queue, no alerting** | `sync_queue_repository.dart:50-58`, `sync_service.dart:341-349` |
| C9 | Deletes: soft-delete locally sets `is_deleted=1`; enqueued operation becomes `delete` when `payload['is_deleted'] == true` | `sync_service.dart:376-378` |
| C10 | Cloud RLS enabled on all 11 tables but policy is `"Dev Access" FOR ALL USING (true) WITH CHECK (true)` — fully permissive | `supabase_schema.sql:248-290` |
| C11 | All sync uses the **anon key**; no JWT, no `auth.uid()`, no per-user RLS context | `sync_service.dart:255` (`Supabase.instance.client`) |
| C12 | Direct SQLite file access bypasses all app-level checks; database is not encrypted (sqflite, no SQLCipher) | `database_helper.dart` (plain `openDatabase`), `pubspec.yaml` (no sqlcipher dependency) |

### 2.4 Authorization findings (D)

| # | Location | Reliance | Problem |
|---|----------|----------|---------|
| D1 | `DashboardShell._menuItems` | None — all 8 menu items shown to every logged-in user | No role-based menu gating (`dashboard_shell.dart:34-43`) |
| D2 | `AttendanceContent` / `AttendanceStore` / `AttendanceRepository.upsertAttendanceForSession` | None — any user can mark/edit attendance for any student/class/subject/date | No assigned-class scope, no teacher-subject binding enforcement, no correction window |
| D3 | `TeachersContent` add/edit/delete teacher | None | Any user can create staff accounts incl. plaintext passwords |
| D4 | `StudentsContent` add/promote/delete student | None | Any user can modify any student record |
| D5 | `SettingsContent.addAcademicSession` / `institute_store.dart` add/delete department/class/subject | None | No admin-only guard |
| D6 | `LeaveContent.updateStatus` (approve/reject leave) | None — `requesterName` is a free-text string, not tied to `currentUser` | No approval workflow, no role restriction on approvers |
| D7 | `auth_store.updateProfile` | Any logged-in user can change own display name/email | No role restriction; no audit |
| D8 | `userRepository.authenticate` | Returns `User.role` but callers never branch on it | Role data collected, unused |

## 3. Current Database Schema and Relationships (v6)

All tables use `TEXT PRIMARY KEY` UUIDs; every synced table has `institute_id TEXT NOT NULL DEFAULT 'default_institute'`, `is_synced INTEGER NOT NULL DEFAULT 0`, `sync_status TEXT NOT NULL`, `is_deleted INTEGER NOT NULL DEFAULT 0`.

**Core tables:**

1. `departments(id, name, code UNIQUE, description, is_active, created_at, updated_at, sync_status, is_deleted, institute_id, is_synced)`
2. `academic_sessions(id, name, start_date, end_date, is_current, created_at, updated_at, sync_status, is_deleted, institute_id, is_synced)`
3. `users(id, username UNIQUE, password_hash, display_name, email, role DEFAULT 'admin', ..., institute_id, is_synced)` — app login accounts.
4. `classes(id, name, section, room, class_name, current_year, department_id (nullable), academic_session_id (nullable), ..., institute_id, is_synced)`
5. `teachers(id, name, subject, email, username, password PLAINTEXT, class_id (nullable), is_active, employee_code, designation, department_id (nullable), ..., institute_id, is_synced)` — **parallel to users; no FK to users.id**.
6. `students(id, name, roll_number, class_id, roll_no, full_name, registration_no, father_name, department_id, academic_session_id, current_year, status, is_active, ..., institute_id, is_synced)`
7. `subjects(id, name, code, teacher_name, class_id, department_id, academic_session_id, year, subject_type, contact_hours, teacher_id (nullable), ..., institute_id, is_synced)` — `teacher_id` references teachers but no FK declared in DDL.
8. `attendance_sessions(id, subject_code, department_id, faculty_id, session_date, academic_session_id, class_id, year, subject_id, remarks, ..., institute_id, is_synced)`
9. `attendance_records(id, session_id, student_id NOT NULL, date, status, check_in_time, check_out_time, ..., institute_id, is_synced, UNIQUE(session_id, student_id), FK student_id → students.id)`
10. `leave_requests(id, requester_name FREE TEXT, leave_type, start_date, end_date, reason, status default pending, ..., institute_id, is_synced)` — no requester user_id FK.
11. `lab_inventory(id, item_name, department_id, category, current_stock, unit, reorder_level, ..., institute_id, is_synced)`
12. `sync_queue(id, entity_type, entity_id, operation, payload, created_at, retry_count, last_error)` — local only.


## 4. Current Synchronization Behavior

1. Any repository write sets `sync_status='PENDING'`/`is_synced=0` and calls `SyncService.schedulePush(table, idColumn, idValue)` (`sync_service.dart:115-130`), which fires `unawaited _pushLocalRow` immediately if Supabase is ready.
2. `_pushLocalRow` reads the local row, converts via `toSupabaseJson()`, calls `_upsert` → `client.from(table).upsert(payload + institute_id)` (`sync_service.dart:218-262`).
3. Background timer every 60s (`flushInterval`) calls `flushSyncQueue`: tops up queue from all unsynced rows (`_enqueueUnsyncedRows`, batch 100 per table), then drains up to 100 queue items (`_drainQueue`).
4. On success: queue item deleted, local row marked `is_synced=1, sync_status='SYNCED'` with `updated_at` CAS; on CAS mismatch the row remains unsynced for retry.
5. On failure: `retry_count++`, `last_error` stored, item remains in queue and is retried indefinitely (no cap, no dead letter).
6. `retagLocalRows(instituteId)` re-tags all rows to a new institute id when a cloud user's metadata overrides `SupabaseConfig.instituteId` (`auth_store.dart:157-163`, `sync_service.dart:182-216`) — a **tenant-confusion risk**: any user who signs into cloud with a different institute_id causes ALL local rows to be re-tagged and re-pushed under the new tenant.

**Authorization in sync:** none at the data layer. RLS is fully permissive (`supabase_schema.sql:250-289`). The anon key is embedded in source as fallback (`supabase_config.dart:18-19`). Direct Postgres access bypasses app checks entirely. There is no mechanism to reject a sync operation that violates business rules (e.g. a teacher correcting attendance after the deadline).

**Relationships:** student→class (class_id), student→department/session, subject→class/teacher/department/session, attendance_record→student (+session), attendance_session→subject/class/department. `users` has **no relationship** to `teachers` or `students` — app accounts and directory records are decoupled.


## 5. Security Vulnerabilities and Architectural Limitations

For each concern: **Risk**, **Current evidence**, **Remedy**.

### V1 — Client-side authorization only; role never enforced (Critical)
- **Risk:** Any authenticated user can access every module (attendance, teachers, students, settings, reports). A teacher can delete students or change settings. Horizontal and vertical privilege escalation is trivial.
- **Evidence:** `dashboard_shell.dart:34-43` (ungated menu); D1–D8 above; `UserRole` unused for UI gating.
- **Remedy:** Server-authorized permission checks enforced at repository/service layer + UI menu gating derived from the same permission model (§8).

### V2 — Unsalted SHA-256 password hashing (Critical)
- **Risk:** Fast offline cracking; identical passwords produce identical hashes (no salt); rainbow-table viable.
- **Evidence:** `auth_store.dart:66`, `user_repository.dart:24-31`, `fresh_database_creator.dart:265-267`.
- **Remedy:** Migrate to Argon2id/bcrypt/scrypt with per-user salt; pepper in secure storage; rehash at next login; never log passwords.

### V3 — Hardcoded default admin credentials exposed in UI and source (Critical)
- **Risk:** `admin`/`Admin@123` is pre-filled on the login screen, revealed by "Forgot password?", and seeded on every new install. Compromise of one device compromises the institute admin account.
- **Evidence:** `app_constants.dart:31-34`, `login_screen.dart:31-35,351-363`, `fresh_database_creator.dart:269-281`.
- **Remedy:** Remove default credentials from UI; force password change on first admin login; deliver temporary credentials out-of-band.

### V4 — Plaintext teacher passwords in parallel credential store (Critical)
- **Risk:** `teachers.password` stores passwords in plaintext; separate from `users` table with no single sign-on.
- **Evidence:** `faculty_repository.dart:57,94`; v6 `teachers` DDL.
- **Remedy:** Eliminate `teachers.username/password`; link staff directory records to `users` via `user_id` FK; authenticate only through `users`.

### V5 — Supabase fallback credentials embedded in source (Critical)
- **Risk:** `supabase_config.dart` contains a fallback Supabase URL and publishable (anon) key committed to source; any client can connect to the project. Anon key + permissive RLS = full read/write on all synced tables from anywhere.

### V10 — Push-only sync with permissive RLS and no server authorization (High)
- **Risk:** A compromised local database can inject/modify cloud rows under the default institute; no server-side validation of business rules (correction windows, locked marks, department scope); conflicts silently overwritten by last upsert.
- **Evidence:** `supabase_schema.sql` RLS `WITH CHECK (true)`; `sync_service.dart:254-262` upsert-only; no pull.
- **Remedy:** Enforce RLS using JWT `institute_id` claim; add server-side validation (Edge Functions/Postgres triggers); implement pull with conflict resolution; dead-letter queue for rejected items.

### V11 — Tenant re-tagging by any cloud sign-in (High)
- **Risk:** `_adoptInstituteId` + `retagLocalRows` re-tags ALL local rows to the institute_id from whoever signs into Supabase next — cross-tenant data leakage/corruption in a multi-college future.
- **Evidence:** `auth_store.dart:157-163`, `sync_service.dart:182-216`.
- **Remedy:** Bind institute to device/account at enrollment; never re-tag from an unverified cloud metadata claim; require admin action for tenant changes.

### V12 — No audit trail (High)
- **Risk:** Attacks or mistakes (attendance changes, grade corrections) cannot be attributed or detected.
- **Evidence:** No `audit_logs` table anywhere; `updated_at` only.
- **Remedy:** Append-only audit log (actor, action, entity, old/new values, timestamp, offline-queued).

### V13 — Leave requests use free-text `requester_name`, not linked to user (Medium)
- **Risk:** Impersonation; approver cannot verify who applied.
- **Evidence:** `leave_requests.requester_name TEXT`, `leave_store.dart:41-47`.
- **Remedy:** `requester_user_id` FK to `users`; auto-populate from session.

### V14 — Teachers table allows self-attendance / no staff-attendance module (Medium per spec)
- **Risk:** Spec states teachers cannot modify their own staff attendance — but no staff attendance module exists at all, so the requirement is unaddressed rather than violated.
- **Evidence:** No staff attendance table; `attendance_records.student_id → students` only.
- **Remedy:** In scope for phase 2 (staff attendance with self-modification bar).

### V15 — No protection for published marks / fees data (Medium)
- **Risk:** Spec requires locked published marks and restricted financial visibility; neither module exists, so no enforcement possible today.
- **Evidence:** No `examinations`/`results`/`fees` tables.

### Architectural limitations (non-vulnerability)

- L1: Single institute hard-coded (`default_institute`); spec assumes one college today but design should be tenant-ready.
- L2: One-way sync only; offline devices never receive cloud-made changes (e.g. accounts created by admin on web).

## 6. Recommended Authorization Architecture

Principles: **never trust the client**, centralize permissions, enforce at repository/service layer (server-side where possible), UI gating is convenience only.

```
Actor (Authenticated principal) → Permission → Scope (institute / department / assigned-class / record-owner) → Operation
```

### 6.1 New identity model

- `users` remains the login account table. Add: `auth_user_id` (Supabase auth.users link), `is_suspended`, `suspended_at`, `suspended_reason`, `failed_login_attempts`, `locked_until`, `password_changed_at`, `last_login_at`, `password_hash` (rehash to Argon2id at next login).
- `roles` table: predefined roles (Principal, Vice Principal, Admin, HOD, Teacher, Accountant, Laboratory In-charge, Assistant, Student, Parent/Guardian) + custom roles per institute.
- `role_permissions`: role → permission grants.
- `user_roles`: many-to-many user ↔ roles (a user may hold multiple roles).
- `permissions` registry: codename + description (e.g. `attendance.mark`, `attendance.correct_after_deadline`, `students.view`, `fees.view_payment_status`, `fees.view_details`, `users.manage`, `leave.approve`).
- `user_departments`: user ↔ department scope.
- `user_assigned_classes`: user ↔ class scope (teachers).
- `students.user_account_id` → `users.id` (student account); `parents` table + `parent_children` link (verified relationship, e.g. via registration/OTP workflow — out of scope for phase 1, documented).

### 6.2 Enforcement layers

1. **UI layer:** menu items and action buttons visible only if `PermissionService.has(permission, scope)` — cosmetic only.
2. **Service/repository layer (local):** every mutating repository call checks `PermissionService` against the current `AuthStore` user + scope (department/class/record owner). Returns `UnauthorizedException`.
3. **Cloud layer (Supabase):** RLS policies using `request.jwt.claims` → `institute_id` + role/permission claims; service-role only for trusted server functions; Edge Functions for sensitive workflows (marks correction approval).
4. **Offline cache:** permissions snapshot stored encrypted locally with session TTL; stale cache degrades to read-only or blocks writes until revalidated.

### 6.3 Spec-specific rules encoded


## 7. Proposed Database Entities and Relationships

New local tables (SQLite, mirrored to Supabase):

| Table | Purpose |
|-------|---------|
| `roles` | id, name (unique), code, description, is_custom, institute_id, is_deleted, sync fields |
| `permissions` | id, code (unique), description, module |
| `role_permissions` | role_id, permission_id (PK pair) |
| `user_roles` | user_id, role_id (PK pair) |
| `user_departments` | user_id, department_id |
| `user_assigned_classes` | user_id, class_id |
| `attendance_correction_windows` | id, class_id, subject_id, date, window_end, created_by |
| `attendance_corrections` | id, attendance_record_id, old_status, new_status, corrected_by, reason, approved_by, approved_at, status (pending/approved/rejected) |
| `audit_logs` | id, actor_user_id, action, entity_type, entity_id, old_values, new_values, created_at, institute_id |
| `parents` | id, name, email, phone, ..., institute_id |
| `parent_children` | parent_id, student_id, verification_status, verified_at |
| `student_user_accounts` | student_id → users.id (nullable) |
| `auth_sessions` (local) | id, user_id, expires_at, idle_until, revoked |

Modified tables:


## 8. Proposed Permission-Enforcement Strategy

Create `PermissionService` (singleton, injectable):

```dart
class PermissionService {
  bool has(User user, String permission,
      {String? departmentId, String? classId, String? recordOwnerId})
```

Checks (ordered):

1. `user == null || user.is_suspended → false`
2. Super-role bypass (Admin/Principal) for institute-wide operations.
3. Role permission grant contains `permission`.
4. Scope check: if `departmentId` required → user in `user_departments`; if `classId` required → user in `user_assigned_classes`; if record-owner → `recordOwnerId == user.id` (or linked student/parent relationship).

Enforcement points:

- `AuthStore.login`: check suspension/lockout before creating session; increment `failed_login_attempts` on failure, lock after N.
- `AuthStore.init()` restoration: re-check suspension and session TTL; reject → logout.
- Repository wrappers: `attendance_repository.upsertAttendance` → require `attendance.mark` (+ class scope + window) or `attendance.correct_after_deadline`.

## 9. Proposed Offline-Session and Synchronization Policy

| Area | Policy |
|------|--------|
| Session lifetime | Absolute TTL (e.g. 30 days) + idle timeout (e.g. 8 hours); stored in SecureStorage with expiry; checked on app resume and `init()`. |
| Restoration | Re-verify `users.is_suspended`, `locked_until`, password age; if invalid → clear session, force login. |
| Offline writes | Allowed for granted permissions using cached permission snapshot; stamped `sync_status='PENDING'`. |
| Sync authorization | Pre-validate locally against cached permissions; on cloud, RLS + server validation; rejected/dead-letter items surfaced to admin with reason, never silently dropped. |
| Conflict resolution | Last-write-wins by `updated_at` (existing) extended with per-field audit; deletes propagate as `is_deleted=1` upserts (tombstones) rather than hard deletes, to avoid resurrecting. |
| Tenant safety | `institute_id` bound at enrollment; `retagLocalRows` removed or restricted to admin-initiated tenant transfer with full re-sync. |
| Revocation | Suspension/deletion written as a high-priority sync item; local cache checked on every resume; suspended users downgraded to read-only immediately offline. |

- `student_repository`, `teacher_repository`, `department_repository`, `leave_repository` → role-scoped checks.
- Sync: reject locally any operation that would violate the actor's permissions (pre-validation); cloud RLS rejects the rest; rejected items go to a dead-letter queue with reason, visible to admin.

Offline behavior: cached permission grants (encrypted) used when offline; writes requiring server validation queued and rejected on sync if policy violated; user notified.

- `users`: add `auth_user_id`, `is_suspended`, `suspended_at`, `failed_login_attempts`, `locked_until`, `password_changed_at`.

## 10. Phased Implementation Plan

### Phase 0 — Approval & Foundation (no app behavior change yet)

- Get this audit report and the specification approved.
- Remove hardcoded Supabase fallback credentials from `supabase_config.dart` (replace with required `--dart-define`).
- Design permission codes, role list, and correction-window config with stakeholders.
- **Deliverable:** approved plan + credential-removal commit.

### Phase 1 — Identity model & local enforcement (SQLite only; no sync behavior change)

- Add tables: `roles`, `permissions`, `role_permissions`, `user_roles`, `user_departments`, `user_assigned_classes`, `audit_logs`, `auth_sessions`.
- Alter `users`: add suspension/lockout fields and `auth_user_id`.
- Alter `teachers`: add `user_id` FK; deprecate plaintext `username`/`password` (keep column, stop using).
- Migration script(s) v7+ (non-destructive; seed predefined roles + permissions + assign seed admin).
- `PermissionService` + enforcement in `AuthStore.login`/`init` (suspension, lockout, session TTL) and in `AttendanceRepository` (correction window stub).
- Remove default credentials from `LoginScreen`; remove pre-fill and credential reveal.
- **Deliverable:** local authorization compiles; unit tests for PermissionService, login suspension, lockout; manual QA of role-gated menus.

### Phase 2 — Attendance correction workflow

- Add `attendance_correction_windows`, `attendance_corrections` tables; `marked_by_user_id` and locked flags on `attendance_records`.
- UI: correction-window config, teacher marking restricted to assigned classes, post-deadline correction requests with HOD/Admin approval, audit log entries.
- Rule: teacher cannot modify own staff attendance (staff-attendance scaffold).
- **Deliverable:** correction workflow functional offline; tests for window logic and self-modification bar.

### Phase 3 — Student/parent accounts & financial visibility

- `students.user_account_id`, `parents`, `parent_children` (verified link workflow).
- `fees`/`payments` skeleton tables; `fees.view_payment_status` vs `fees.view_details` enforcement.
- Student and parent login paths (local auth via `users`).
- **Deliverable:** role-scoped data visibility per spec.

### Phase 4 — Published marks lock & exam results


## 11. Acceptance Criteria and Regression Tests

### 11.1 Acceptance criteria (must be demonstrable before sign-off)

1. **Login:** Invalid credentials rejected; suspended/locked accounts cannot log in or restore session; default credentials not present anywhere in UI/source.
2. **Role gating:** A Teacher cannot open Students/Classes/Settings management modules; a HOD cannot access Accountant-only fees detail; menu visibility matches `PermissionService`.
3. **Attendance:** Teacher can mark attendance only for assigned classes during the window; after window, correction requires HOD/Admin approval and creates an audit record; teacher cannot correct own staff attendance record.
4. **Marks/fees:** Published marks cannot be changed directly by teacher; teacher sees payment status only, not financial detail.
5. **Student/parent:** Parent account sees only linked, verified children.
6. **Sync:** A change made by a user without permission is rejected locally and never uploaded; a cloud-made suspension takes effect on next app resume; rejected sync items are visible and actionable.
7. **Offline:** Session expires after TTL; app usable offline for granted permissions; database file not readable as plaintext (encryption).
8. **Audit:** Every sensitive mutation (attendance correction, marks correction, role change, user suspension) produces an audit log entry with actor and timestamp.

### 11.2 Regression tests (new, to be added; no existing tests modified beyond ensuring they pass)

| Test | Location (suggested) |
|------|----------------------|
| `PermissionService.has()` grants/denies by role, department, class, owner | `test/core/services/permission_service_test.dart` |
| Login rejects suspended user; lockout after N failures | `test/core/state/auth_store_test.dart` (new) |
| Session restore rejects expired/suspended session | `test/core/state/auth_store_test.dart` |
| Attendance mark outside window denied without `correct_after_deadline` | `test/core/repositories/attendance_repository_test.dart` (new) |
| Teacher self-attendance modification barred | `test/core/repositories/attendance_repository_test.dart` |

## 12. Decisions Requiring Confirmation

The following cannot be decided unilaterally and need stakeholder sign-off before implementation:

1. **Cloud identity strategy:** Is Supabase Auth the system of record for users going forward, or does local SQLite remain authoritative with Supabase only as a dumb sync target? This drives whether `auth_user_id` is mandatory and whether login should verify against Supabase first.
2. **Password hashing migration:** Argon2id vs bcrypt; how to rehash existing SHA-256 hashes (rehash at next login vs forced reset).
3. **Default admin provisioning:** How should the first admin be created in production (invite email, out-of-band temporary password, CLI seed)?
4. **Correction window defaults:** Default attendance correction deadline (e.g. end of day? 48 hours?) and who can configure it per class/subject.
5. **Multi-tenant future:** GILT serves one college now; should `institute_id` RLS be built for multiple colleges now, or keep single-tenant with `default_institute`?
6. **Student/parent verification:** What constitutes a "verified" parent-child link (document upload, OTP, in-person admin verification)?
7. **Encryption scope:** SQLCipher for the entire database vs selective field encryption for sensitive columns (passwords, father name, financial data)?
8. **Sync conflict policy:** Last-write-wins vs field-level merge vs manual resolution UI for conflicting attendance corrections.
9. **Approval authority matrix:** Which roles can approve attendance corrections, marks corrections, leave, and user suspensions — exactly (e.g. HOD for department, Admin institute-wide, Principal override)?
10. **Retention of `teachers.password`:** Remove column in v7 migration or keep deprecated (keeping increases risk but eases backward compatibility)?

## 13. Verification Notes for Reviewers

All "Verified" findings in this report were confirmed by reading the listed source files at the paths given. No application file was modified, no database was opened or altered, and no migration was created during this audit. Assumptions are explicitly labeled; where the codebase is silent (e.g. absence of a table), absence was confirmed by enumerating migrations, models, repositories, and `supabase_schema.sql`.

The hardcoded Supabase fallback URL/anon key in `supabase_config.dart:18-19` is **not** reproduced in this report (per the no-secrets rule); its presence and risk are noted without values.

### Recommended next step

Review and approve the phased plan (Section 10) and the decisions list (Section 12). Upon approval, Phase 0 (credential removal + plan sign-off) can begin immediately. No code changes have been made to date.

| Existing login widget tests still pass | `test/features/auth/presentation/login_screen_test.dart` |
| Existing migration tests (v3, v5) still pass | `test/core/database/schema_migration_v*_test.dart` |
| Sync queue behavior unchanged (retry, markFailed) | `test/core/repositories/sync_queue_repository_test.dart` |

All tests run via `flutter test`; no destructive DB operations in tests (use in-memory or temp-path databases via `DatabaseHelper.forTesting`).

- `examinations`, `results` tables; `published` flag; correction workflow (`results.correct_published` → approval → audit).
- **Deliverable:** locked marks enforcement.

### Phase 5 — Cloud authorization & sync hardening

- Replace Dev Access RLS with institute-scoped authenticated policies (`institute_id = jwt claim`).
- Add `users.auth_user_id` mapping; require Supabase session for online writes; Edge Functions for sensitive approvals.
- Pull/download with conflict resolution; dead-letter queue UI for rejected sync items; retry limits.
- **Deliverable:** sync enforces authorization server-side; no data loss on conflict.

### Phase 6 — Offline hardening

- SQLCipher database encryption; EncryptedSharedPreferences; session TTL enforcement on resume; revocation propagation; encrypted permission cache.
- Penetration test checklist (local DB extraction, SharedPreferences extraction, offline replay, sync tampering).
- **Deliverable:** offline-security acceptance criteria met.

- `teachers`: add `user_id` FK → users.id; deprecate `username`/`password`.
- `attendance_records`: add `marked_by_user_id`, `corrected_after_deadline` flag, `locked_at`.
- `leave_requests`: add `requester_user_id` FK → users.id.

Relationships: user —< user_roles >— role —< role_permissions >— permission; user —< user_departments >— department; user —< user_assigned_classes >— class; student —< parent_children >— parent; attendance_records — attendance_corrections. All new tables carry `institute_id` for RLS scoping.

- Teacher may `attendance.mark` only for classes assigned via `user_assigned_classes`, during `attendance_correction_window` (configurable start/end datetime per class/subject).
- After window: `attendance.correct_after_deadline` required (HOD/Admin+).
- Teacher cannot modify own staff attendance (staff attendance records have `staff_user_id`; rule: `subject.user_id == actor.id → forbidden` unless role ≥ HOD).
- Published marks locked: `results.published = true` → direct teacher update forbidden; correction requires `results.correct_published` workflow (request → approver → audit log).
- Payment status: `fees.view_payment_status` for teachers of the student's class; `fees.view_details` restricted to Accountant/Admin+.
- Parent sees only linked children (`parent_children` verified link).

- L3: `role` enum too narrow for the 11 organizational roles; no custom roles/permissions.
- L4: No correction-window or published-lock concept in attendance schema.
- L5: Tests exist only for login UI, migrations, sync queue, and models — no authorization tests.

- **Evidence:** `supabase_config.dart:18-19`; `supabase_schema.sql:248-290` ("Dev Access" USING true/WITH CHECK true).
- **Remedy:** Remove fallback credentials; require `--dart-define` at build time; replace Dev Access policies with institute-scoped authenticated policies keyed to JWT claims before production.

### V6 — No link between Supabase Auth identities and local users (High)
- **Risk:** Cloud sign-in success/failure has no bearing on local authorization; a deleted/suspended Supabase user can still log in locally; audit cannot attribute cloud writes to local users.
- **Evidence:** `auth_store.dart:135-153` (metadata only reads institute_id); no `auth_user_id` column.
- **Remedy:** Add `users.auth_user_id` (nullable UUID → Supabase `auth.users.id`), require cloud session for online operations, map sync operations to the authenticated user.

### V7 — Session restoration without re-authentication or expiry (High)
- **Risk:** Stolen device = persistent session until explicit logout; password changes/suspensions never take effect for already-restored sessions; no idle/absolute timeout.
- **Evidence:** `auth_store.dart:40-57`.
- **Remedy:** Session TTL (absolute + idle), refresh via cloud or local challenge on resume, store session expiry in SecureStorage.

### V8 — No account suspension or lockout (High)
- **Risk:** Compromised or terminated accounts remain usable; brute-force unconstrained.
- **Evidence:** No `is_suspended`/`failed_attempts`/`locked_until` columns or UI.
- **Remedy:** Add suspension flags, failed-attempt counter with lockout, admin suspension UI, enforce on login and restoration; propagate suspensions via sync as data (authoritative source: cloud/admin).

### V9 — Local database unencrypted; SharedPreferences plaintext (High)
- **Risk:** Physical access or backup extraction yields all credentials and personal data (students, fathers' names, attendance).
- **Evidence:** `database_helper.dart` plain `openDatabase`; `pubspec.yaml` lacks SQLCipher; `shared_preferences` plaintext.
- **Remedy:** SQLCipher for SQLite (offline-first requirement), EncryptedSharedPreferences for tokens/credentials, screen-lock binding where platform allows.

**Missing vs specification:** no `roles`, `role_permissions`, `user_roles`, `user_departments`, `user_assigned_classes`, `parents`, `guardians`, `student_user_accounts`, `examinations`, `results`, `fees`, `payments`, `attendance_corrections`, `audit_logs`, `auth_sessions`, `institutes` (multi-tenant) tables.


### 2.5 Offline security findings (E)

| # | Finding | Evidence |
|---|---------|----------|
| E1 | SQLite database file is not encrypted | `pubspec.yaml` (sqflite only), `database_helper.dart` |
| E2 | `pref_user_id`/`pref_user_role` in SharedPreferences plaintext; no encryption, no expiry, no binding to device | `auth_store.dart:76-84`, `app_constants.dart:10-11` |
| E3 | Cached institute data (`InstituteStore` lists) held in memory only; no encrypted cache | `institute_store.dart` |
| E4 | Offline session never expires; restoration requires only `pref_user_id` | `auth_store.dart:40-57` |
| E5 | No offline permission cache; permissions would have to be computed from local role/assigned scopes | Absence confirmed |
| E6 | No revocation: a suspended/deleted cloud account keeps working offline indefinitely | Absence of suspension + restoration logic |
| E7 | Pending changes validated only locally (field presence); no server-side authorization re-check at sync time | `sync_service.dart:254-262` (upsert with permissive RLS) |
| E8 | Rejected sync operations silently retried forever with growing `retry_count` | `sync_service.dart:341-349` |
| E9 | No protection against privilege escalation: local `users.role` can be edited directly in SQLite by anyone with device/backup access | `user_repository.dart` has no role-change authorization guard |

| B10 | `attendance_sessions`: subject_code, department_id, faculty_id, session_date, class_id, subject_id, academic_session_id — session "owner" recorded as plaintext `faculty_id` with no FK enforcement of who may correct | `fresh_database_creator.dart`; `attendance_session.dart` |
| B11 | Foreign keys enabled (`PRAGMA foreign_keys = ON`) but most FK columns are nullable TEXT without declared FK constraints in DDL (e.g. `students.class_id`) | `database_helper.dart:44`, `fresh_database_creator.dart` DDL |

| A7 | `UserRole` enum = `{admin, teacher, student}` only — no principal, vice principal, HOD, accountant, lab in-charge, assistant, parent | `app_constants.dart:192-205` | Verified |
| A8 | No link between Supabase Auth users and local `users` table | `auth_store.dart` (no auth.user id storage), `supabase_schema.sql` (no users mapping table) | Verified |
| A9 | `teachers` table stores **plaintext passwords** in a parallel `username`/`password` credential store | `faculty_repository.dart:35-82`, v6 schema in `fresh_database_creator.dart` | Verified |
| A10 | No failed-attempt tracking, lockout, or suspension | Absence of columns/UI confirmed by reading `users` schema and all repositories | Verified |


**Yes.** Local SQLite authentication is the source of truth. Supabase sign-in failure never blocks local login (`auth_store.dart:61-64,73-74`). The app is explicitly designed so offline login works even when Supabase is unavailable or misconfigured. This is by design for offline operation, but it means **local account state (suspension, password change, role change) is never re-validated against the cloud**, and a suspended account can still open a local session because restoration never checks suspension status.

### 1.9 Account suspension enforcement (verified)

**Not implemented.** The only account-state flags are:

- `users.is_deleted` (soft delete) — checked in `getById` and `authenticate` queries (`user_repository.dart`).
- `teachers.is_active` — checked nowhere at query time; only displayed (`teacher.isActive` in UI).

There is **no `is_suspended`, `disabled_at`, `locked_until`, or `failed_login_attempts` column**, no lockout policy, and no UI to suspend/reactivate accounts. Suspension per the specification cannot be enforced today.

5. `notifyListeners()`; UI navigates to `HomeScreen`/`DashboardShell`.

Failure handling (verified): `login` returns `null`; `LoginScreen._handleLogin` shows a generic snackbar "Invalid username or password" — no distinction between unknown user / wrong password / disabled account, no failed-attempt counter, no lockout (`login_screen.dart:93-98`).

- **No user-management UI:** No screen to create/edit app users, reset passwords, or assign roles exists in the current feature set.

- **Entry point:** `main.dart` → `AttendanceApp` → `LoginScreen` (always the home route; no auth wrapper redirects).

This report documents verified findings (with file paths, classes, and functions), current schema, sync behavior, vulnerabilities, and a phased implementation plan with acceptance criteria. No code changes were made during this phase.
