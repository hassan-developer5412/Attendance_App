# attendance_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Web + Windows + Android support

The app uses a platform-specific SQLite database factory so the shared Dart
code can run on browser and native platforms. Native platforms continue to use
SQLite/FFI; browser builds use `sqflite_common_ffi_web`, which stores the SQLite
database in IndexedDB.

### Web first-time setup

From the project root:

```bash
flutter pub get
dart run tool/setup_web_database.dart
```

The setup command installs the required `sqlite3.wasm` and `sqflite_sw.js`
files into `web/`. Keep the same browser port during local development when
you want the web database to persist between runs.

Run in Chrome with:

```bash
flutter run -d chrome
```

### Windows first-time setup

The original project did not include a Windows runner. Generate the native
Windows project files once with the Flutter SDK:

```bash
flutter config --enable-windows-desktop
flutter create --platforms=windows .
flutter run -d windows
```

The Dart application and database code are already prepared for Windows.

### Android

Existing Android support is preserved:

```bash
flutter devices
flutter run -d <android-device-id>
```

### Startup behavior

The application now renders a loading screen while database/store
initialization runs. If startup fails, the UI shows the underlying error and a
Retry button instead of leaving the window/browser blank.
