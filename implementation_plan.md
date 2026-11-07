# Implementation Plan: Fix "Could not find the correct Provider<RBACStore>" Error

## 1. Executive Summary

**Error:** `Could not find the correct Provider<RBACStore> above this DashboardShell Widget`

**Trigger:** Occurs immediately after successful login when the app navigates from `LoginScreen` → `HomeScreen` → `DashboardShell`.

**Root Cause:** `RBACStore` is used by `DashboardShell` via `context.watch<RBACStore>()` (line 270 of `dashboard_shell.dart`), but `RBACStore` is **not registered** in the `MultiProvider` widget tree in `main.dart`. The `MultiProvider` only provides `authStore`, `instituteStore`, `attendanceStore`, and `leaveStore` — `RBACStore` is missing.

This is a pure Flutter Provider scoping issue. No Supabase schema or data changes are required to fix this specific error.

## 2. Detailed Root Cause Analysis

### 2.1 Where the error occurs

**File:** `lib/features/dashboard/presentation/dashboard_shell.dart`
**Method:** `_getActiveItems(BuildContext context)` (line 268)
**Line 270:** `final rbacStore = context.watch<RBACStore>();`

`DashboardShell.build()` (line 516) calls `_getActiveItems(context)`, which calls `context.watch<RBACStore>()`. The `watch` call looks up the Provider tree for a `ChangeNotifierProvider<RBACStore>`. Since none exists above `DashboardShell`, the `provider` package throws `ProviderNotFoundError`.

### 2.2 Where providers are registered

**File:** `lib/main.dart`
**Class:** `AttendanceApp` (line 202)
**Method:** `build(BuildContext context)` (line 217)
**Lines 218-234:**

```dart
return MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: authStore),
    ChangeNotifierProvider.value(value: instituteStore),
    ChangeNotifierProvider.value(value: attendanceStore),
    ChangeNotifierProvider.value(value: leaveStore),
  ],
  child: MaterialApp(
    ...
    home: const LoginScreen(),
  ),
);
```

`RBACStore` is absent from this list. Because `MaterialApp` (and therefore all routes including `DashboardShell`) is a child of `MultiProvider`, any widget that tries to read `RBACStore` from the provider tree will fail.

## 3. Files Affected

| File | Role | Change Required? |
|------|------|------------------|
| `lib/main.dart` | Composition root; creates `MultiProvider` and `AttendanceApp` | **Yes** — add `RBACStore` provider, create instance, pass to `AttendanceApp` |
| `lib/features/dashboard/presentation/dashboard_shell.dart` | Consumer of `RBACStore` via `context.watch<RBACStore>()` | No — code is correct; it just needs the provider to exist |
| `lib/core/state/auth_store.dart` | Has `attachRbacStore()` and calls `_rbacStore?.loadForUser()` / `_rbacStore?.clear()` | No — already wired to use `RBACStore` once attached |

## 4. Supabase Assessment

**No Supabase changes are required for this fix.**

### Why Supabase is not involved:

- The error is a Flutter `Provider` scoping issue, not a database or API issue.
- `RBACStore` loads roles, permissions, and user-role assignments from **local SQLite** repositories (`RoleRepository`, `UserRoleRepository`, `PermissionRepository`), not from Supabase.
- Supabase is used in this app for best-effort cloud authentication and background sync only; its failure is explicitly swallowed and never blocks local login or dashboard access.
- `SupabaseConfig.isReady` being `false` (offline mode) does not affect whether `RBACStore` can be provided in the widget tree.


## 5. Implementation Steps

### Step 1: Import `RBACStore` in `main.dart`

**File:** `lib/main.dart`

Add the import for `RBACStore` alongside the existing store imports:

```dart
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/leave_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';  // ADD THIS
```

### Step 2: Create `RBACStore` instance and pass it to `AttendanceApp`

**File:** `lib/main.dart`
**Method:** `_AttendanceBootstrapState._initializeApp()` (line 62)

After creating `authStore`, `instituteStore`, `attendanceStore`, and `leaveStore`, create an `RBACStore` instance and pass it to the `AttendanceApp` constructor:

```dart
final authStore = AuthStore();
await authStore.init();

final instituteStore = InstituteStore();
await instituteStore.init();

final attendanceStore = AttendanceStore();

final leaveStore = LeaveStore();
await leaveStore.loadAll();

final rbacStore = RBACStore();  // ADD THIS

authStore.attachRbacStore(rbacStore);  // ADD THIS — enables login/logout to load/clear grants

return AttendanceApp(
  authStore: authStore,
  instituteStore: instituteStore,
  attendanceStore: attendanceStore,
  leaveStore: leaveStore,
  rbacStore: rbacStore,  // ADD THIS
);
```

### Step 3: Add `rbacStore` parameter to `AttendanceApp` constructor

**File:** `lib/main.dart`
**Class:** `AttendanceApp` (line 202)

Add a `required RBACStore rbacStore` parameter to the constructor and store it as a field:

```dart
class AttendanceApp extends StatelessWidget {
  const AttendanceApp({
    super.key,
    required this.authStore,
    required this.instituteStore,
    required this.attendanceStore,
    required this.leaveStore,
    required this.rbacStore,  // ADD THIS
  });

  final AuthStore authStore;
  final InstituteStore instituteStore;
  final AttendanceStore attendanceStore;
  final LeaveStore leaveStore;
  final RBACStore rbacStore;  // ADD THIS
```

### Step 4: Register `RBACStore` in the `MultiProvider`

**File:** `lib/main.dart`
**Method:** `AttendanceApp.build()` (line 217)

Add `RBACStore` to the `providers` list:

```dart
return MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: authStore),
    ChangeNotifierProvider.value(value: instituteStore),
    ChangeNotifierProvider.value(value: attendanceStore),
    ChangeNotifierProvider.value(value: leaveStore),
    ChangeNotifierProvider.value(value: rbacStore),  // ADD THIS

## 6. Verification Checklist

After implementing the above steps, verify:

- [ ] App compiles without errors (`flutter analyze` passes)
- [ ] Hot restart (not just hot reload) is performed after adding the provider — per the error message's guidance: "You added a new provider in your `main.dart` and performed a hot-reload. To fix, perform a hot-restart."
- [ ] Login succeeds and navigates to `DashboardShell` without `ProviderNotFoundError`
- [ ] `DashboardShell` menu items appear according to the user's role (student / teacher / HOD / admin)
- [ ] `PermissionGuard` widgets correctly show/hide based on loaded RBAC grants
- [ ] Logout clears RBAC state and returns to `LoginScreen` without errors
- [ ] App works offline (Supabase not configured) — `RBACStore` loads from local SQLite

## 7. Rollback Plan

If the fix causes issues, revert the changes to `lib/main.dart`:

1. Remove the `rbacStore` parameter from `AttendanceApp` constructor and its field.
2. Remove `ChangeNotifierProvider.value(value: rbacStore)` from `MultiProvider`.
3. Remove the `RBACStore` import.
4. Remove `RBACStore` instance creation and `attachRbacStore()` call from `_initializeApp()`.

This restores the original (broken) state, which can then be re-diagnosed.

## 8. Notes

- **Hot restart required:** The error message explicitly states that adding a new provider in `main.dart` requires a hot-restart (not just hot-reload) because the provider tree is rebuilt at `runApp()` time.
- **`RBACStore` is a `ChangeNotifier`:** It is safe to use with `ChangeNotifierProvider.value()` since it extends `ChangeNotifier` (see `rbac_store.dart` line 25).
- **No `MultiProvider` nesting issue:** `DashboardShell` is a descendant of `MaterialApp`, which is a child of `MultiProvider`. Providers registered in `MultiProvider` are visible to all descendants. This is the correct placement — `RBACStore` should be at the same level as the other stores so all dashboard widgets can access it.
- **`PermissionGuard` already handles missing provider:** It catches `ProviderNotFoundException` and permits display. After this fix, it will actively enforce permissions instead of falling back to permissive mode.


### Step 5: Verify `RBACStore` is available to `DashboardShell`

After the above changes, the provider tree will be:

```
MultiProvider
├── ChangeNotifierProvider.value(authStore)
├── ChangeNotifierProvider.value(instituteStore)
├── ChangeNotifierProvider.value(attendanceStore)
├── ChangeNotifierProvider.value(leaveStore)
└── ChangeNotifierProvider.value(rbacStore)   ← NEW
    └── MaterialApp
        └── LoginScreen → HomeScreen → DashboardShell
            └── context.watch<RBACStore>() now succeeds
```

When `DashboardShell.build()` calls `_getActiveItems(context)` → `context.watch<RBACStore>()`, the provider will be found and the error will be resolved.

### Step 6: Verify RBAC loading on login

`AuthStore.login()` already calls `_rbacStore?.loadForUser(user.id)` (line 288 of `auth_store.dart`). Once `attachRbacStore(rbacStore)` is called in `_initializeApp()` (Step 2), the `_rbacStore` field on `AuthStore` will be non-null, so RBAC grants will be loaded automatically after login. No changes needed to `auth_store.dart`.

### Step 7: Verify RBAC clearing on logout

`AuthStore.logout()` already calls `_rbacStore?.clear()` (line 609 of `auth_store.dart`). No changes needed.

### When Supabase changes WOULD be needed (future work, not this fix):

If the team decides to load RBAC grants from Supabase tables (e.g., `public.roles`, `public.user_roles`, `public.permissions`) instead of/in addition to local SQLite, then:
- Supabase table schemas would need to exist for roles, permissions, and user_roles.
- `RBACStore.loadForUser()` would need to fetch from Supabase when online.
- This is **out of scope** for fixing the current `ProviderNotFoundError`.

| `lib/core/widgets/permission_guard.dart` | Secondary consumer; already handles missing provider gracefully | No |
| `lib/core/state/rbac_store.dart` | The `RBACStore` class itself (a `ChangeNotifier`) | No |


### 2.3 How RBACStore is designed to be used

**File:** `lib/core/state/auth_store.dart`
- `AuthStore` has an `attachRbacStore(RBACStore store)` method (line 106) that stores an `RBACStore` reference.
- `AuthStore.login()` calls `_rbacStore?.loadForUser(user.id)` (line 288) to load RBAC grants after successful login.
- `AuthStore.logout()` calls `_rbacStore?.clear()` (line 609) to clear grants on logout.
- This means `AuthStore` is **designed to work with an `RBACStore` instance**, but `main.dart` never creates or attaches one.

**File:** `lib/core/widgets/permission_guard.dart`
- `PermissionGuard.build()` uses `Provider.of<RBACStore>(context, listen: true)` (line 46) but wraps it in a try/catch for `ProviderNotFoundException`, so it degrades gracefully when `RBACStore` is missing. It will **not** crash — but it also won't enforce permissions until the provider is registered.

### 2.4 Navigation flow that triggers the error

1. `LoginScreen._handleLogin()` succeeds → `authStore.login()` returns a user.
2. `LoginScreen` calls `Navigator.pushReplacement` to `HomeScreen()` (line 98-102 of `login_screen.dart`).
3. `HomeScreen.build()` returns `const DashboardShell()` (line 11 of `home_screen.dart`).
4. `DashboardShell.build()` → `_getActiveItems(context)` → `context.watch<RBACStore>()` → **CRASH** because `RBACStore` is not in the provider tree.
