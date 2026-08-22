import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
    const bg = Color(0xFF0F0F0F);
    const fg = Color(0xFFE0E0E0);
    const accent = Color(0xFF00A8FF);
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
                  Text('> OPENGYM',
                      style: mono.copyWith(
                          color: accent,
                          fontSize: 28,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_isSignUp ? '// create account' : '// sign in',
                      style: mono.copyWith(color: fg.withAlpha(153))),
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
      labelStyle: mono.copyWith(color: fg.withAlpha(128)),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: fg.withAlpha(51)),
        borderRadius: BorderRadius.circular(4),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: accent),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
