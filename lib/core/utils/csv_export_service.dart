/// Cross-platform CSV export service.
///
/// On Web the CSV is downloaded via a browser anchor click (no `dart:io`).
/// On native platforms (Windows/Android) the CSV is written to a file using
/// `dart:io` and the local file path is returned.
///
/// The platform-specific implementation defines [saveCsvFile]; this file
/// conditionally re-exports the right one for the target platform.
library;

export 'csv_export_service_web.dart'
    if (dart.library.io) 'csv_export_service_native.dart';