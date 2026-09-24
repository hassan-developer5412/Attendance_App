import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/theme/app_theme.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/classes_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/students_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/teachers_content.dart';
import 'package:attendance_app/features/dashboard/presentation/widgets/institute_form_dialogs.dart';

void main() {
  Widget wrap(Widget child) {
    return ChangeNotifierProvider(
      create: (_) => InstituteStore(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('add class dialog submits without crashing', (tester) async {
    await tester.pumpWidget(wrap(const ClassesContent()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add class'));
    await tester.pumpAndSettle();

    expect(find.text('Add class'), findsWidgets);

    await tester.enterText(find.byKey(const Key('classNameField')), 'Grade 7');
    await tester.enterText(find.byKey(const Key('classSectionField')), 'B');
    await tester.enterText(find.byKey(const Key('classRoomField')), 'Room 9');

    await tester.ensureVisible(find.byKey(const Key('confirmAddButton')));
    await tester.tap(find.byKey(const Key('confirmAddButton')));
    await tester.pumpAndSettle();

    expect(find.text('Grade 7 — B'), findsOneWidget);
  });

  testWidgets('add teacher dialog opens and submits without crashing', (tester) async {
    await tester.pumpWidget(wrap(const TeachersContent()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add teacher'));
    await tester.pumpAndSettle();

    expect(find.byType(AddTeacherDialog), findsOneWidget);

    await tester.enterText(find.byKey(const Key('teacherNameField')), 'Nadia Ali');
    await tester.enterText(find.byKey(const Key('teacherSubjectField')), 'Art');

    await tester.ensureVisible(find.byKey(const Key('confirmAddButton')));
    await tester.tap(find.byKey(const Key('confirmAddButton')));
    await tester.pumpAndSettle();

    expect(find.text('Teacher added'), findsOneWidget);
    expect(find.text('Nadia Ali'), findsOneWidget);
  });

  testWidgets('add student dialog opens and submits without crashing', (tester) async {
    await tester.pumpWidget(wrap(const StudentsContent()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add student'));
    await tester.pumpAndSettle();

    expect(find.byType(AddStudentDialog), findsOneWidget);

    await tester.enterText(find.byKey(const Key('studentNameField')), 'Bilal Hussain');
    await tester.enterText(find.byKey(const Key('studentRollField')), '09A-99');

    await tester.ensureVisible(find.byKey(const Key('confirmAddButton')));
    await tester.tap(find.byKey(const Key('confirmAddButton')));
    await tester.pumpAndSettle();

    expect(find.text('Student added'), findsOneWidget);
    expect(find.text('Bilal Hussain'), findsOneWidget);
  });
}
