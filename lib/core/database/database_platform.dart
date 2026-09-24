// Platform-specific database configuration.
// Web is the default implementation; native platforms override it when
// dart.library.io is available. This also keeps dart:io out of web builds.
export 'database_platform_web.dart'
    if (dart.library.io) 'database_platform_io.dart';
