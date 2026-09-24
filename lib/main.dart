import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/database_platform.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/leave_store.dart';
import 'package:attendance_app/core/theme/app_theme.dart';
import 'package:attendance_app/features/auth/presentation/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    final authStore = AuthStore();
    await authStore.init();

    final instituteStore = InstituteStore();
    await instituteStore.init();

    final attendanceStore = AttendanceStore();

    final leaveStore = LeaveStore();
    await leaveStore.loadAll();

    return AttendanceApp(
      authStore: authStore,
      instituteStore: instituteStore,
      attendanceStore: attendanceStore,
      leaveStore: leaveStore,
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
    required this.attendanceStore,
    required this.leaveStore,
  });

  final AuthStore authStore;
  final InstituteStore instituteStore;
  final AttendanceStore attendanceStore;
  final LeaveStore leaveStore;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authStore),
        ChangeNotifierProvider.value(value: instituteStore),
        ChangeNotifierProvider.value(value: attendanceStore),
        ChangeNotifierProvider.value(value: leaveStore),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const LoginScreen(),
      ),
    );
  }
}
