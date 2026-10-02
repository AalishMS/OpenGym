import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Central access point for the Supabase client and the current user.
class SupabaseService {
  SupabaseService._();

  static bool passwordRecoveryPending = false;
  static StreamSubscription<AuthState>? _recoverySubscription;

  // Baked-in Supabase config so EVERY build (any IDE, any `flutter run`/`build`,
  // CI) has online support with no --dart-define flags. A --dart-define or
  // --dart-define-from-file still OVERRIDES these, e.g. to point a build at a
  // different Supabase project.
  //
  // SUPABASE_ANON_KEY here is a *publishable* key (prefix `sb_publishable_`):
  // it is meant to ship in client bundles/APKs and is already public in the
  // hosted web build. RLS is the real security boundary. NEVER put a
  // service_role / `sb_secret_` key here. The checked-in publishable defaults
  // are deliberate; don't replace them with empty defaults.
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
    await _recoverySubscription?.cancel();
    // The SDK replays its last auth event. Subscribe before runApp so a
    // cold-start recovery link is retained through subsequent token refreshes.
    _recoverySubscription = auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          passwordRecoveryPending = true;
        } else if (state.event == AuthChangeEvent.signedOut) {
          passwordRecoveryPending = false;
        }
      },
      onError: (Object error) {
        debugPrint('Authentication recovery failed: ${error.runtimeType}');
      },
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static GoTrueClient get auth => client.auth;

  static User? get currentUser => isConfigured ? client.auth.currentUser : null;

  static String? get currentUserId => currentUser?.id;

  static Future<void> signIn(String email, String password) =>
      auth.signInWithPassword(email: email.trim(), password: password);

  static Future<void> signUp(String email, String password) =>
      auth.signUp(email: email.trim(), password: password);

  static Future<void> signOut() => auth.signOut();

  static const recoveryAppUrl = 'io.opengym.app://reset-password/';
  static const recoveryWebUrl = 'https://open-gym.netlify.app/';

  static Future<void> requestPasswordReset(String email) =>
      auth.resetPasswordForEmail(
        email.trim(),
        redirectTo:
            kIsWeb
                ? Uri.base
                    .replace(query: 'password_reset=true', fragment: '')
                    .toString()
                : recoveryAppUrl,
      );

  static Future<void> updatePassword(
    String password, {
    String? expectedUserId,
  }) {
    if (expectedUserId != null &&
        auth.currentSession?.user.id != expectedUserId) {
      throw const AuthException(
        'Your account changed. Open the reset link again before saving a password.',
      );
    }
    return auth.updateUser(UserAttributes(password: password));
  }
}
