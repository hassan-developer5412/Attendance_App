import 'package:attendance_app/core/constants/app_constants.dart';

/// Central configuration for the Supabase backend.
///
/// Credentials are read from `--dart-define` values first and fall back to the
/// placeholder constants below, which can be filled in for local testing:
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=YOUR-ANON-KEY
/// ```
///
/// The app is offline-first: when Supabase is not configured nothing here is
/// used, every push becomes a no-op, and SQLite remains the single source of
/// truth.
class SupabaseConfig {
  SupabaseConfig._();

  static const String _defineUrl = String.fromEnvironment(
    'https://hbmllywlxkkfxtycvqwx.supabase.co',
    defaultValue: '',
  );
  static const String _defineKey = String.fromEnvironment(
    'sb_publishable_B5f-ZSNXgE0ultSJ8OJBfA_Xq98-jco',
    defaultValue: '',
  );

  /// Optional hard-coded fallback for local development.
  /// Prefer `--dart-define` so real keys never land in version control.
  static const String _fallbackUrl = '';
  static const String _fallbackKey = '';

  static String get supabaseUrl =>
      _defineUrl.isNotEmpty ? _defineUrl : _fallbackUrl;

  static String get supabaseAnonKey =>
      _defineKey.isNotEmpty ? _defineKey : _fallbackKey;

  /// Whether usable credentials are present at all.
  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  /// Set to `true` by `main()` after `Supabase.initialize()` succeeds.
  /// Never poke `Supabase.instance` before this is `true` (it asserts).
  static bool isInitialized = false;

  /// The single gate every Supabase code path must check first.
  static bool get isReady => isConfigured && isInitialized;

  /// Central tenant id stamped onto every Supabase payload.
  ///
  /// Defaults to [AppConstants.defaultInstituteId]; `AuthStore` refreshes it
  /// from the signed-in user's `institute_id` metadata and persists it.
  static String instituteId = AppConstants.defaultInstituteId;
}