/// Native implementation of CSV export (Windows / Android / iOS / macOS).
///
/// Writes the CSV to a file alongside the app's SQLite database using
/// `dart:io` + `sqflite`'s `getDatabasesPath()`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Saves [content] as a CSV file named [fileName] next to the local SQLite
/// database and returns the absolute file path.
Future<String?> saveCsvFile({
  required String fileName,
  required String content,
}) async {
  final dbDir = await getDatabasesPath();
  final directory = Directory(dbDir);
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  final file = File(p.join(dbDir, fileName));
  await file.writeAsString(content);
  return file.path;
}