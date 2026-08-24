import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';

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
    // On theme now: colours come from tokens so the screen honours the user's
    // chosen accent and light/dark mode instead of hardcoded terminal values.
    final fg = textPrimaryColor(context);
    final muted = textSecondaryColor(context);
    final accent = accentColor(context);
    final onAccent = onAccentColor(context);
    final mono = GoogleFonts.jetBrainsMono();

    return Scaffold(
      backgroundColor: backgroundColor(context),
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
                  Text('> OPENGYM',
                      style: mono.copyWith(
                          color: accent,
                          fontSize: 28,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_isSignUp ? '// create account' : '// sign in',
                      style: mono.copyWith(color: muted)),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _emailController,
                    style: mono.copyWith(color: fg),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: _decoration('email', mono, muted, accent),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    style: mono.copyWith(color: fg),
                    obscureText: true,
                    decoration: _decoration('password', mono, muted, accent),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!,
                        style: mono.copyWith(
                            color: errorColor(context), fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentFillColor(context),
                      foregroundColor: onAccent,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.button),
                    ),
                    child: _loading
                        ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: onAccent))
                        : Text(_isSignUp ? '[CREATE ACCOUNT]' : '[SIGN IN]',
                            style: mono.copyWith(
                                fontWeight: FontWeight.bold, color: onAccent)),
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
      String label, TextStyle mono, Color muted, Color accent) {
    return InputDecoration(
      labelText: label,
      labelStyle: mono.copyWith(color: muted),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: borderColor(context)),
        borderRadius: AppRadius.field,
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: accent),
        borderRadius: AppRadius.field,
      ),
    );
  }
}
