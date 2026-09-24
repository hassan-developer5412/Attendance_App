import 'package:flutter/material.dart';

import 'package:attendance_app/features/dashboard/presentation/dashboard_shell.dart';

/// Home screen that delegates to the responsive [DashboardShell].
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DashboardShell();
  }
}
