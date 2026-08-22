import 'package:supabase_flutter/supabase_flutter.dart';

/// Central access point for the Supabase client and the current user.
class SupabaseService {
  SupabaseService._();

  // Baked-in Supabase config so EVERY build (any IDE, any `flutter run`/`build`,
  // CI) has online support with no --dart-define flags. A --dart-define or
  // --dart-define-from-file still OVERRIDES these, e.g. to point a build at a
  // different Supabase project.
  //
  // SUPABASE_ANON_KEY here is a *publishable* key (prefix `sb_publishable_`):
  // it is meant to ship in client bundles/APKs and is already public in the
  // hosted web build. RLS is the real security boundary. NEVER put a
  // service_role / `sb_secret_` key here. This is a deliberate exception to the
  // "no Supabase literals in the repo" note in online-support-plan/phase-5 —
  // don't "fix" it back to empty defaults.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://uhvemfdgxlhpalmkulnv.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_E31uJl-4yfbbAxihs_71KQ_GaKMlVEt',
  );

  /// Whether Supabase config is present. With the baked-in defaults above this
  /// is normally always true; it becomes false only if a build passes an empty
  /// override, in which case the app runs fully offline.
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
