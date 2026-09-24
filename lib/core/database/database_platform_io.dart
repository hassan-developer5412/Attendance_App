import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Configures SQLite for native platforms.
Future<void> configureDatabase() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

/// Returns a platform-appropriate database path.
Future<String> databaseFilePath(String fileName) async {
  final basePath = await getDatabasesPath();
  return '$basePath${Platform.pathSeparator}$fileName';
}
