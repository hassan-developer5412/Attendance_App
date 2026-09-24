import 'package:sqflite_common_ffi_web/setup.dart';

Future<void> main() async {
  await setupSqfliteWebBinaries();
  print('Web SQLite files installed in web/.');
}
