import 'package:flutter/material.dart';

import 'package:attendance_app/features/users/presentation/user_management_content.dart';

/// Standalone screen wrapper for User & Staff Management.
class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User & Staff Management'),
      ),
      body: const UserManagementContent(),
    );
  }
}
