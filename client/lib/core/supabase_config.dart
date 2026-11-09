/// Supabase connection credentials and initialization helper for the Flutter client.
///
/// Credentials are read from environment variables (injectable at build time)
/// so the module imports cleanly in offline/test environments. The actual
/// `Supabase.initialize` call is deferred to [`initialize`].
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  SupabaseConfig._();

  /// Project URL supplied at build time via `--dart-define=SUPABASE_URL=...`.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://placeholder.supabase.co',
  );

  /// Modern Publishable API Key (`sb_publishable_...`) supplied at build time via
  /// `--dart-define=SUPABASE_PUBLISHABLE_KEY=...` with fallback to legacy
  /// `--dart-define=SUPABASE_ANON_KEY=...` (retiring early 2027).
  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: 'placeholder-publishable-key',
    ),
  );

  /// Backward-compatible alias for legacy references.
  static String get supabaseAnonKey => supabasePublishableKey;

  /// Initializes the Supabase Flutter client. Safe to call before `runApp`.
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  }

  /// Convenience accessor to the initialized Supabase client.
  static SupabaseClient get client => Supabase.instance.client;
}
