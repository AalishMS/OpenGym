# Phase 1 — Supabase project + auth gate

**Goal:** stand up a Supabase project, wire the client into the app, and gate the whole UI behind
login. After this phase the app requires an account to enter, but does **not** sync yet (that's
Phase 3).

**Depends on:** Phase 0 landed and verified.

**Backend work:** you create a Supabase project (no SQL yet — that's Phase 2).

---

## Step 1.0 — Create the Supabase project (console, one-time)

1. Go to <https://supabase.com>, sign in, **New project**. Pick a name (e.g. `opengym`), a strong
   database password (save it in a password manager), and a region close to you.
2. Wait for provisioning (~2 min).
3. **Project Settings → API.** Copy two values — you'll pass them to the app via `--dart-define`:
   - **Project URL** → `SUPABASE_URL` (looks like `https://abcdefgh.supabase.co`)
   - **anon public** key → `SUPABASE_ANON_KEY` (a long JWT). This one is **safe to ship** (RLS
     protects the data). Do **not** copy the `service_role` key anywhere near the app.
4. **Authentication → Providers → Email:** ensure Email is enabled. For a friends-only project,
   **turn OFF "Confirm email"** (Authentication → Providers → Email → "Confirm email" toggle) so
   sign-up logs the user straight in without a confirmation link. (If you leave it on, you must also
   do the Site URL / redirect config in Phase 5 and users must click an email link.)

> Keep the URL + anon key handy for every `flutter run` / `flutter build` from here on.

---

## Step 1.1 — Add dependencies

Edit `pubspec.yaml` `dependencies:` — add:

```yaml
  supabase_flutter: ^2.5.0
```

(`uuid` was already added in Phase 0.) Then:

```bash
flutter pub get
```

> `connectivity_plus: ^6.0.0` is optional polish for Phase 3 (detect offline→online). Not required;
> Phase 3 works with try/catch + resume triggers alone. Add it only if you want the extra trigger.

---

## Step 1.2 — New file `lib/services/supabase_service.dart`

Thin wrapper so the rest of the app never imports `supabase_flutter` directly.

```dart
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
      anonKey: supabaseAnonKey,
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
```

---

## Step 1.3 — Init Supabase in `main.dart`

**Edit A — import** (top of `lib/main.dart`, with the other imports):

```dart
import 'services/supabase_service.dart';
import 'auth/auth_gate.dart';
```

**Edit B — call init in `main()`.** Find the existing `main()` (it calls `HiveService.init()`
inside a try/catch). Add the Supabase init **after** Hive init succeeds. REPLACE:

```dart
  try {
    await HiveService.init();
  } catch (e) {
```

with:

```dart
  try {
    await HiveService.init();
    await SupabaseService.init();
  } catch (e) {
```

> Rationale: Hive must be ready first (local source of truth). If `SUPABASE_URL`/`ANON_KEY` are
> absent, `SupabaseService.init()` is a no-op and the app runs offline exactly as before.

**Edit C — swap the home widget.** Find the `MaterialApp` home (around `main.dart:112`). REPLACE:

```dart
            home: const AppShell(),
```

with:

```dart
            home: const AuthGate(),
```

> If `AppShell` is imported at the top of `main.dart` and now becomes unused, `flutter analyze` will
> warn. Leave the import — `AuthGate` references `AppShell`, so keep it importable; if the analyzer
> still flags it as unused in `main.dart`, remove only the `main.dart` import line for `AppShell`
> (the widget itself is untouched).

---

## Step 1.4 — New file `lib/auth/auth_gate.dart`

Watches auth state. No session → `LoginScreen`; session → `AppShell`. When Supabase isn't
configured (offline-only build), it falls straight through to `AppShell` so the app still works.

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../screens/login_screen.dart';
import '../app_shell.dart'; // adjust path if AppShell lives elsewhere

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // Offline-only build (no Supabase config): behave exactly like before.
    if (!SupabaseService.isConfigured) {
      return const AppShell();
    }

    return StreamBuilder<AuthState>(
      stream: SupabaseService.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = SupabaseService.auth.currentSession;
        if (session != null) {
          return const AppShell();
        }
        return const LoginScreen();
      },
    );
  }
}
```

> **Import path for `AppShell`:** in the summary, `main.dart` used `home: const AppShell()`, so
> `AppShell` is already imported there — open `main.dart`, copy the exact import path it uses for
> `AppShell`, and use that same path here (it may be `../app_shell.dart` or
> `../screens/app_shell.dart`). If the "find" import doesn't resolve, fix the path — do not guess.

> **Phase 4 hook:** the adoption call (`adoptLocalDataIfNeeded`) and the "clear boxes if user
> changed" logic will be added here, in the `session != null` branch, in Phase 4. For now the gate
> only routes.

---

## Step 1.5 — New file `lib/screens/login_screen.dart`

Email/password sign in + sign up in the app's terminal aesthetic (JetBrains Mono, dark). Adjust
colors to match your theme constants if you have them; the structure is what matters.

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/supabase_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password required');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isSignUp) {
        await SupabaseService.signUp(email, password);
      } else {
        await SupabaseService.signIn(email, password);
      }
      // AuthGate's StreamBuilder reacts to the auth change and swaps the screen.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0A0A0A);
    const fg = Color(0xFFE0E0E0);
    const accent = Color(0xFF00E676);
    final mono = GoogleFonts.jetBrainsMono();

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('OpenGym',
                      style: mono.copyWith(
                          color: accent,
                          fontSize: 28,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_isSignUp ? '// create account' : '// sign in',
                      style: mono.copyWith(color: fg.withOpacity(0.6))),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _emailController,
                    style: mono.copyWith(color: fg),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: _decoration('email', mono, fg, accent),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    style: mono.copyWith(color: fg),
                    obscureText: true,
                    decoration: _decoration('password', mono, fg, accent),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!,
                        style: mono.copyWith(
                            color: const Color(0xFFFF5252), fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: bg,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: bg))
                        : Text(_isSignUp ? 'CREATE ACCOUNT' : 'SIGN IN',
                            style: mono.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                              _isSignUp = !_isSignUp;
                              _error = null;
                            }),
                    child: Text(
                      _isSignUp
                          ? 'Have an account? Sign in'
                          : 'No account? Create one',
                      style: mono.copyWith(color: accent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(
      String label, TextStyle mono, Color fg, Color accent) {
    return InputDecoration(
      labelText: label,
      labelStyle: mono.copyWith(color: fg.withOpacity(0.5)),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: fg.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(4),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: accent),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
```

> Colors are self-contained here so this compiles even if you don't have shared theme constants.
> If you DO have a theme file, swap the local `bg`/`fg`/`accent` for your constants for consistency.

---

## Step 1.6 — Sign-out tile in Settings

In `lib/screens/settings_screen.dart`, DATA section (the `_SectionHeader 'DATA'` block, around
lines 88–137). Add a sign-out tile after the existing tiles (e.g. after "CLEAR ALL"). It should
only show when signed in.

Add inside the DATA `Column`'s children, after the CLEAR ALL tile:

```dart
          if (SupabaseService.currentUser != null)
            _buildSettingsTile(
              icon: Icons.logout,
              title: 'SIGN OUT',
              subtitle: SupabaseService.currentUser?.email ?? 'Signed in',
              onTap: () async {
                await SupabaseService.signOut();
                // AuthGate reacts and shows LoginScreen automatically.
              },
              accent: accent,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              border: border,
            ),
```

Add the import at the top of `settings_screen.dart`:

```dart
import '../services/supabase_service.dart';
```

> Match the exact parameter names your `_buildSettingsTile` uses (from the summary:
> `icon, title, subtitle, onTap, accent, textPrimary, textSecondary, border, [isDestructive, error]`).
> If your local signature differs, adapt the named args — do not invent parameters.

---

## Step 1.7 — Analyze & run

```bash
flutter analyze
flutter run --dart-define=SUPABASE_URL=YOUR_URL --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

---

## Verification checklist

- [ ] With **no** `--dart-define` flags: app launches straight into `AppShell` (offline mode), no
      crash — `SupabaseService.isConfigured` is false and `AuthGate` falls through.
- [ ] With the flags: launching shows the **LoginScreen**.
- [ ] **Sign up** with a new email/password → lands in the app (AppShell). (Requires "Confirm email"
      OFF in Supabase, per Step 1.0.)
- [ ] Kill and reopen the app (same dart-defines) → still logged in (session persisted), goes
      straight to AppShell.
- [ ] **Sign out** from Settings → returns to LoginScreen.
- [ ] **Wrong password** → visible error message, no crash.
- [ ] `flutter analyze` clean.

## Suggested commit

```
feat(phase-1): supabase auth gate, login screen, sign-out
```
