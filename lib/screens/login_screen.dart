import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../widgets/app_button.dart';
import '../widgets/app_wordmark.dart';

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
  bool _obscurePassword = true;
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
      setState(() => _error = 'Email and password required.');
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

    return Scaffold(
      backgroundColor: backgroundColor(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppWordmark(fontSize: 28),
                    const SizedBox(height: 8),
                    Text(
                      _isSignUp ? 'Create account' : 'Sign in',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isSignUp
                          ? 'Sync your training across devices.'
                          : 'Continue with your saved plans and history.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _emailController,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: fg),
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: _decoration('Email', muted, accent),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: fg),
                      autofillHints: [
                        _isSignUp
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      obscureText: _obscurePassword,
                      onSubmitted: _loading ? null : (_) => _submit(),
                      decoration: _decoration(
                        'Password',
                        muted,
                        accent,
                        suffixIcon: IconButton(
                          tooltip:
                              _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                          onPressed:
                              () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: errorColor(context)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    AppButton.primary(
                      label: _isSignUp ? 'Create account' : 'Sign in',
                      onPressed: _loading ? null : _submit,
                      child:
                          _loading
                              ? SizedBox(
                                height: 18,
                                width: 18,
                                child: Semantics(
                                  label:
                                      _isSignUp
                                          ? 'Creating account'
                                          : 'Signing in',
                                  value: 'In progress',
                                  liveRegion: true,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: onAccentColor(context),
                                  ),
                                ),
                              )
                              : null,
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed:
                          _loading
                              ? null
                              : () => setState(() {
                                _isSignUp = !_isSignUp;
                                _error = null;
                              }),
                      child: Text(
                        _isSignUp
                            ? 'Have an account? Sign in'
                            : 'No account? Create one',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(
    String label,
    Color muted,
    Color accent, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: muted),
      suffixIcon: suffixIcon,
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
