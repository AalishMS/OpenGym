import 'package:supabase_flutter/supabase_flutter.dart';

/// Central access point for the Supabase client and the current user.
class SupabaseService {
  SupabaseService._();

  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// True when compile-time config was provided. When false, the app still runs
  /// fully offline (auth screens should surface a clear "not configured" state
  /// rather than crash).
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static Future<void> init() async {
    if (!isConfigured) return; // offline-only build; skip Supabase entirely
    await Supabase.initialize(
      url: supabaseUrl,
      // The dart-define is still named SUPABASE_ANON_KEY (what the Supabase
      // dashboard calls the "anon public" key); supabase_flutter renamed the
      // parameter to publishableKey and accepts the legacy anon key here.
      publishableKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static GoTrueClient get auth => client.auth;

  static User? get currentUser =>
      isConfigured ? client.auth.currentUser : null;

  static String? get currentUserId => currentUser?.id;

  static Future<void> signIn(String email, String password) =>
      auth.signInWithPassword(email: email.trim(), password: password);

  static Future<void> signUp(String email, String password) =>
      auth.signUp(email: email.trim(), password: password);

  static Future<void> signOut() => auth.signOut();
}
