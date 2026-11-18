import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/models/attendance_record.dart';
import 'package:attendance_app/core/repositories/academic_session_repository.dart';
import 'package:attendance_app/core/repositories/class_repository.dart';
import 'package:attendance_app/core/repositories/department_repository.dart';
import 'package:attendance_app/core/repositories/faculty_repository.dart';
import 'package:attendance_app/core/repositories/student_repository.dart';
import 'package:attendance_app/core/repositories/subject_repository.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/dashboard_content.dart';

class FakeAttendanceStore extends AttendanceStore {
  FakeAttendanceStore({
    this.lateCount = 2,
    this.overview = const {'total': 10, 'present': 8, 'rate': 80.0},
    this.weekly = const [],
    this.distribution = const {},
    this.activity = const [],
    this.shouldThrow = false,
  });

  final int lateCount;
  final Map<String, dynamic> overview;
  final List<Map<String, int>> weekly;
  final Map<AttendanceStatus, int> distribution;
  final List<AttendanceRecord> activity;
  bool shouldThrow;

  @override
  Future<int> todayLateCount() async {
    if (shouldThrow) throw Exception('Simulated database failure');
    return lateCount;
  }

  @override
  Future<Map<String, dynamic>> todayOverview() async {
    if (shouldThrow) throw Exception('Simulated database failure');
    return overview;
  }

  @override
  Future<List<Map<String, int>>> weeklyStats() async {
    if (shouldThrow) throw Exception('Simulated database failure');
    return weekly;
  }

  @override
  Future<Map<AttendanceStatus, int>> monthlyDistribution() async {
    if (shouldThrow) throw Exception('Simulated database failure');
    return distribution;
  }

  @override
  Future<List<AttendanceRecord>> recentActivity({int limit = 5}) async {
    if (shouldThrow) throw Exception('Simulated database failure');
    return activity;
  }
}

void main() {
  late Database db;
  late DatabaseHelper dbHelper;
  late InstituteStore instituteStore;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await FreshDatabaseCreator.createAndSeed(db);
    dbHelper = DatabaseHelper.forTesting(db);

    instituteStore = InstituteStore(
      classRepository: ClassRepository(dbHelper: dbHelper),
      facultyRepository: FacultyRepository(dbHelper: dbHelper),
      studentRepository: StudentRepository(dbHelper: dbHelper),
      subjectRepository: SubjectRepository(dbHelper: dbHelper),
      departmentRepository: DepartmentRepository(dbHelper: dbHelper),
      academicSessionRepository: AcademicSessionRepository(dbHelper: dbHelper),
      databaseHelper: dbHelper,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Dashboard Loading Resilience Tests', () {
    test('InstituteStore manages isLoading flag and handles init errors gracefully', () async {
      expect(instituteStore.isLoading, isFalse);

      final initFuture = instituteStore.init();
      await initFuture;
      expect(instituteStore.isLoading, isFalse);
      expect(instituteStore.departments.isNotEmpty, isTrue);
    });

    testWidgets('DashboardContent renders spinner while loading and displays content on success', (tester) async {
      final fakeAttendanceStore = FakeAttendanceStore();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<InstituteStore>.value(value: instituteStore),
            ChangeNotifierProvider<AttendanceStore>.value(value: fakeAttendanceStore),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DashboardContent(),
            ),
          ),
        ),
      );

      // Initially shows loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Allow async load to complete
      await tester.pumpAndSettle();

      // Spinner should be gone, content displayed
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Live Overview'), findsOneWidget);
      expect(find.text('Total Students'), findsOneWidget);
    });

    testWidgets('DashboardContent displays error message and Retry button on failure, and Retry works', (tester) async {
      final fakeAttendanceStore = FakeAttendanceStore(shouldThrow: true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<InstituteStore>.value(value: instituteStore),
            ChangeNotifierProvider<AttendanceStore>.value(value: fakeAttendanceStore),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DashboardContent(),
            ),
          ),
        ),
      );

      // Initially shows loading spinner
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Pump to trigger async failure in addPostFrameCallback
      await tester.pumpAndSettle();

      // Should NOT be stuck on spinner
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Should display error UI and Retry button
      expect(find.text('Failed to load dashboard'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);

      // Now recover from failure on retry
      fakeAttendanceStore.shouldThrow = false;

      // Tap Retry button
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pump();

      // After load finishes, error should be gone and content displayed
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Live Overview'), findsOneWidget);
    });
  });
}
