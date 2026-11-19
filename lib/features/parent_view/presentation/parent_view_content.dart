import 'package:flutter/material.dart';

import 'package:attendance_app/features/student_view/presentation/student_self_view_content.dart';

/// Portal for parents to monitor their child's academic schedule, attendance history,
/// leave applications, and institute notices.
///
/// Serves as a clean hook and future extension point for multi-child selection,
/// parent communication channels, and fee status. Currently delegates to
/// [StudentSelfViewContent] for self-service child records.
class ParentViewContent extends StatelessWidget {
  final int initialTab;
  final String? studentId;

  const ParentViewContent({
    super.key,
    this.initialTab = 0,
    this.studentId,
  });

  @override
  Widget build(BuildContext context) {
    // Hook: Routes to the student self view for child records.
    return StudentSelfViewContent(
      initialTab: initialTab,
      studentId: studentId,
    );
  }
}
