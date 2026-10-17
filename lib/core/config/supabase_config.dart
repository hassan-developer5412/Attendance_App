import 'package:attendance_app/core/constants/app_constants.dart';

/// Central configuration for the Supabase backend.
class SupabaseConfig {
  SupabaseConfig._();

  // 1. Reads --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_ANON_KEY=...
  static const String _defineUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String _defineKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  // 2. Hardcoded fallback credentials for local development
  static const String _fallbackUrl = 'https://hbmllywlxkkfxtycvqwx.supabase.co';
  static const String _fallbackKey = 'sb_publishable_B5f-ZSNXgE0ultSJ8OJBfA_Xq98-jco';

  static String get supabaseUrl =>
      _defineUrl.isNotEmpty ? _defineUrl : _fallbackUrl;

  static String get supabaseAnonKey =>
      _defineKey.isNotEmpty ? _defineKey : _fallbackKey;

  /// Whether usable credentials are present at all.
  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  /// Set to `true` by `main()` after `Supabase.initialize()` succeeds.
  static bool isInitialized = false;

  /// The single gate every Supabase code path must check first.
  static bool get isReady => isConfigured && isInitialized;

  /// Central tenant id stamped onto every Supabase payload.
  static String instituteId = AppConstants.defaultInstituteId;
}