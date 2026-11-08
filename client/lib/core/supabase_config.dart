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

  /// Anon key supplied at build time via `--dart-define=SUPABASE_ANON_KEY=...`.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'placeholder-anon-key',
  );

  /// Initializes the Supabase Flutter client. Safe to call before `runApp`.
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  }

  /// Convenience accessor to the initialized Supabase client.
  static SupabaseClient get client => Supabase.instance.client;
}
