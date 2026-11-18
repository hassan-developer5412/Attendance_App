import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:attendance_app/core/config/supabase_config.dart';
import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/database_platform.dart';
import 'package:attendance_app/core/services/sync_service.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/lab_inventory_store.dart';
import 'package:attendance_app/core/state/leave_store.dart';
import 'package:attendance_app/core/state/notice_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart'; // ADD THIS
import 'package:attendance_app/core/state/timetable_store.dart';
import 'package:attendance_app/core/state/user_store.dart';
import 'package:attendance_app/core/theme/app_theme.dart';
import 'package:attendance_app/core/theme/theme_notifier.dart';
import 'package:attendance_app/features/auth/presentation/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase when configured. Any failure (bad URL, no network,
  // missing key) is swallowed so the app keeps running fully offline with
  // SQLite as the single source of truth.
  try {
    if (SupabaseConfig.isConfigured) {
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        publishableKey: SupabaseConfig.supabaseAnonKey,
      );
      SupabaseConfig.isInitialized = true;
    }
  } catch (e, s) {
    SupabaseConfig.isInitialized = false;
    debugPrint('Supabase initialization failed; continuing offline: $e');
    debugPrintStack(stackTrace: s);
  }

  runApp(const AttendanceBootstrap());
}

/// Initializes platform services before constructing the main application.
///
/// Initialization errors are rendered as an actual screen instead of leaving
/// the browser/desktop window blank.
class AttendanceBootstrap extends StatefulWidget {
  const AttendanceBootstrap({super.key});

  @override
  State<AttendanceBootstrap> createState() => _AttendanceBootstrapState();
}

class _AttendanceBootstrapState extends State<AttendanceBootstrap> {
  late Future<AttendanceApp> _appFuture;

  @override
  void initState() {
    super.initState();
    _appFuture = _initializeApp();
  }

  Future<AttendanceApp> _initializeApp() async {
    await configureDatabase();

    // Initialize the database (creates tables on first launch).
    await DatabaseHelper.instance.database;

    // Initialize stores from the database.
    final rbacStore = RBACStore();
    final authStore = AuthStore();
    authStore.attachRbacStore(rbacStore);
    await authStore.init();

    final instituteStore = InstituteStore();
    await instituteStore.init();

    final labInventoryStore = LabInventoryStore();
    await labInventoryStore.init();

    final noticeStore = NoticeStore();
    await noticeStore.init();

    final timetableStore = TimetableStore();
    await timetableStore.init();

    final attendanceStore = AttendanceStore();

    final leaveStore = LeaveStore();
    await leaveStore.loadAll();

    // Initialize UserStore for managing users and staff.
    final userStore = UserStore();
    final themeNotifier = ThemeNotifier();

    // When Supabase pulls remote changes into SQLite (via pullAll), reload
    // every active store from the local database so the UI reflects the
    // canonical data. Set this before start() so the periodic timer also
    // triggers store reloads.
    SyncService.instance.onPullCompleted = () async {
      await instituteStore.init();
      await labInventoryStore.init();
      await noticeStore.init();
      await timetableStore.init();
      await leaveStore.loadAll();
      await userStore.loadUsers();
      await rbacStore.refresh();
      await attendanceStore.reload();
    };

    // Kick off background Supabase sync (no-op unless Supabase is configured
    // and initialized). Failures never block app startup.
    try {
      if (SupabaseConfig.isReady) {
        unawaited(SyncService.instance.start());
      }
    } catch (e, s) {
      debugPrint('Failed to start background sync: $e');
      debugPrintStack(stackTrace: s);
    }

    return AttendanceApp(
      authStore: authStore,
      instituteStore: instituteStore,
      labInventoryStore: labInventoryStore,
      noticeStore: noticeStore,
      timetableStore: timetableStore,
      attendanceStore: attendanceStore,
      leaveStore: leaveStore,
      rbacStore: rbacStore,
      userStore: userStore,
      themeNotifier: themeNotifier,
    );
  }

  void _retry() {
    setState(() {
      _appFuture = _initializeApp();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AttendanceApp>(
      future: _appFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Starting Institute Attendance...'),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: _StartupErrorScreen(
              error: snapshot.error!,
              onRetry: _retry,
            ),
          );
        }

        return snapshot.data!;
      },
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'The app could not finish starting',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'The application is running, but its database or startup services reported an error.',
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      error.toString(),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Root widget for the school / institute attendance system.
class AttendanceApp extends StatelessWidget {
  const AttendanceApp({
    super.key,
    required this.authStore,
    required this.instituteStore,
    required this.labInventoryStore,
    required this.noticeStore,
    required this.timetableStore,
    required this.attendanceStore,
    required this.leaveStore,
    required this.rbacStore,
    required this.userStore,
    required this.themeNotifier,
  });

  final AuthStore authStore;
  final InstituteStore instituteStore;
  final LabInventoryStore labInventoryStore;
  final NoticeStore noticeStore;
  final TimetableStore timetableStore;
  final AttendanceStore attendanceStore;
  final LeaveStore leaveStore;
  final RBACStore rbacStore;
  final UserStore userStore;
  final ThemeNotifier themeNotifier;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authStore),
        ChangeNotifierProvider.value(value: instituteStore),
        ChangeNotifierProvider.value(value: labInventoryStore),
        ChangeNotifierProvider.value(value: noticeStore),
        ChangeNotifierProvider.value(value: timetableStore),
        ChangeNotifierProvider.value(value: attendanceStore),
        ChangeNotifierProvider.value(value: leaveStore),
        ChangeNotifierProvider.value(value: userStore),
        ChangeNotifierProvider.value(value: rbacStore),
        ChangeNotifierProvider.value(value: themeNotifier),
      ],
      child: Consumer<ThemeNotifier>(
        builder: (_, theme, _) => MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: theme.themeMode,
          home: const LoginScreen(),
        ),
      ),
    );
  }
}
