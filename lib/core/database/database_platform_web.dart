import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Configures the experimental SQLite/WebAssembly implementation for browsers.
Future<void> configureDatabase() async {
  databaseFactory = databaseFactoryFfiWeb;
}

/// Web databases are persisted in IndexedDB by sqflite_common_ffi_web.
Future<String> databaseFilePath(String fileName) async => fileName;
