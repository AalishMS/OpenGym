import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_error_message.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_wordmark.dart';

enum _LoginMode { signIn, signUp, resetEmail, newPassword }

class LoginScreen extends StatefulWidget {
  final bool passwordRecovery;
  final VoidCallback? onPasswordRecovered;
  final String? initialError;

  const LoginScreen({
    this.passwordRecovery = false,
    this.onPasswordRecovered,
    this.initialError,
    super.key,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmationFocus = FocusNode();
  late _LoginMode _mode =
      widget.passwordRecovery
          ? _LoginMode.newPassword
          : kIsWeb && Uri.base.queryParameters['reset_password'] == 'true'
          ? _LoginMode.resetEmail
          : _LoginMode.signIn;
  bool _loading = false;
  bool _obscurePassword = true;
  late String? _error = widget.initialError;
  String? _recoveryUserId;
  String? _emailError;
  String? _passwordError;
  String? _confirmationError;
  String? _message;

  bool get _isSignUp => _mode == _LoginMode.signUp;
  bool get _resetEmail => _mode == _LoginMode.resetEmail;
  bool get _newPassword => _mode == _LoginMode.newPassword;

  @override
  void initState() {
    super.initState();
    if (widget.passwordRecovery) {
      _recoveryUserId = SupabaseService.auth.currentSession?.user.id;
    }
  }

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialError != oldWidget.initialError &&
        widget.initialError != null) {
      _error = widget.initialError;
    }
  }

  String get _title => switch (_mode) {
    _LoginMode.signIn => 'Sign in',
    _LoginMode.signUp => 'Create account',
    _LoginMode.resetEmail => 'Reset password',
    _LoginMode.newPassword => 'Choose a new password',
  };
  String get _action =>
      _resetEmail
          ? 'Send reset email'
          : _newPassword
          ? 'Save password'
          : _title;
  String get _progress =>
      _resetEmail
          ? 'Sending reset email'
          : _newPassword
          ? 'Saving password'
          : _isSignUp
          ? 'Creating account'
          : 'Signing in';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmationFocus.dispose();
    super.dispose();
  }

  void _changeMode(_LoginMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _message = null;
      _emailError = null;
      _passwordError = null;
      _confirmationError = null;
      _passwordController.clear();
      _confirmationController.clear();
    });
  }

  Future<void> _beginReset() async {
    if (_loading) return;
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      _changeMode(_LoginMode.resetEmail);
      _emailFocus.requestFocus();
      return;
    }
    // Desktop builds have no registered app-link handler. Request recovery in
    // the browser so the PKCE verifier stays with the browser that opens email.
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final opened = await launchUrl(
        Uri.parse('${SupabaseService.recoveryWebUrl}?reset_password=true'),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      setState(() {
        if (opened) {
          _message =
              'Reset your password in the browser, then return here to sign in.';
        } else {
          _error = 'Could not open password recovery. Try again.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open password recovery. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_loading) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    setState(() {
      _error = null;
      _message = null;
      _emailError =
          _newPassword
              ? null
              : email.isEmpty
              ? 'Enter your email.'
              : !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
              ? 'Enter a valid email address.'
              : null;
      _passwordError =
          _resetEmail
              ? null
              : password.isEmpty
              ? 'Enter your password.'
              : (_newPassword || _isSignUp) && password.length < 6
              ? 'Use at least 6 characters.'
              : null;
      _confirmationError =
          _newPassword && _confirmationController.text != password
              ? 'Passwords do not match.'
              : null;
    });
    if (_emailError != null) {
      _emailFocus.requestFocus();
      return;
    }
    if (_passwordError != null) {
      _passwordFocus.requestFocus();
      return;
    }
    if (_confirmationError != null) {
      _confirmationFocus.requestFocus();
      return;
    }
    setState(() => _loading = true);
    try {
      if (_resetEmail) {
        await SupabaseService.requestPasswordReset(email);
        if (mounted) {
          setState(
            () =>
                _message =
                    'If an account uses this email, you will receive a reset link. Open it on this device${kIsWeb ? ' in this browser' : ''} to choose a new password.',
          );
        }
      } else if (_newPassword) {
        if (_recoveryUserId == null) {
          throw const AuthException(
            'Open a new reset link before saving a password.',
          );
        }
        await SupabaseService.updatePassword(
          password,
          expectedUserId: _recoveryUserId,
        );
        if (!mounted) return;
        setState(() => _message = 'Password updated.');
        // Keep recovery visible through userUpdated/tokenRefreshed events. The
        // user explicitly continues after seeing the successful result.
      } else if (_isSignUp) {
        await SupabaseService.signUp(email, password);
        if (mounted && SupabaseService.auth.currentSession == null) {
          setState(
            () =>
                _message =
                    'Check your email to confirm your account, then sign in.',
          );
        }
      } else {
        await SupabaseService.signIn(email, password);
      }
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final savedPassword = _newPassword && _message == 'Password updated.';
    return Scaffold(
      backgroundColor: backgroundColor(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppWordmark(fontSize: 28),
                    const SizedBox(height: AppSpacing.sm),
                    Semantics(
                      header: true,
                      child: Text(_title, style: theme.headlineMedium),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _resetEmail
                          ? 'Enter your account email to receive a reset link.'
                          : _newPassword
                          ? 'Save a new password for your account.'
                          : _isSignUp
                          ? 'Sync your training across devices.'
                          : 'Continue with your saved plans and history.',
                      style: theme.bodyMedium?.copyWith(
                        color: textSecondaryColor(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    if (!savedPassword) ...[
                      if (!_newPassword) ...[
                        TextField(
                          controller: _emailController,
                          focusNode: _emailFocus,
                          enabled: !_loading,
                          autofillHints: const [AutofillHints.email],
                          keyboardType: TextInputType.emailAddress,
                          textInputAction:
                              _resetEmail
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                          autocorrect: false,
                          onSubmitted:
                              (_) =>
                                  _resetEmail
                                      ? _submit()
                                      : _passwordFocus.requestFocus(),
                          onChanged: (_) {
                            if (_emailError != null) {
                              setState(() => _emailError = null);
                            }
                          },
                          decoration: _decoration('Email', error: _emailError),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      if (!_resetEmail)
                        TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          enabled: !_loading,
                          autofillHints: [
                            _isSignUp || _newPassword
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction:
                              _newPassword
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                          autocorrect: false,
                          enableSuggestions: false,
                          obscureText: _obscurePassword,
                          onSubmitted:
                              (_) =>
                                  _newPassword
                                      ? _confirmationFocus.requestFocus()
                                      : _submit(),
                          onChanged: (_) {
                            if (_passwordError != null) {
                              setState(() => _passwordError = null);
                            }
                          },
                          decoration: _decoration(
                            _newPassword ? 'New password' : 'Password',
                            error: _passwordError,
                            suffixIcon: IconButton(
                              tooltip:
                                  _obscurePassword
                                      ? 'Show password'
                                      : 'Hide password',
                              onPressed:
                                  _loading
                                      ? null
                                      : () => setState(
                                        () =>
                                            _obscurePassword =
                                                !_obscurePassword,
                                      ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                      if (_newPassword) ...[
                        const SizedBox(height: AppSpacing.lg),
                        TextField(
                          controller: _confirmationController,
                          focusNode: _confirmationFocus,
                          enabled: !_loading,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.newPassword],
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          enableSuggestions: false,
                          onSubmitted: (_) => _submit(),
                          onChanged: (_) {
                            if (_confirmationError != null) {
                              setState(() => _confirmationError = null);
                            }
                          },
                          decoration: _decoration(
                            'Confirm password',
                            error: _confirmationError,
                          ),
                        ),
                      ],
                    ],
                    if (_error != null || _message != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error ?? _message!,
                          style: theme.bodySmall?.copyWith(
                            color:
                                _error != null
                                    ? errorColor(context)
                                    : textPrimaryColor(context),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    AppButton.primary(
                      label: savedPassword ? 'Continue' : _action,
                      onPressed:
                          _loading
                              ? null
                              : savedPassword
                              ? widget.onPasswordRecovered
                              : _submit,
                      child:
                          _loading
                              ? Semantics(
                                label: _progress,
                                value: 'In progress',
                                liveRegion: true,
                                child: SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: onAccentColor(context),
                                  ),
                                ),
                              )
                              : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_mode == _LoginMode.signIn)
                      AppButton.text(
                        label: 'Forgot password?',
                        onPressed: _loading ? null : _beginReset,
                      ),
                    if (!_newPassword)
                      TextButton(
                        onPressed:
                            _loading
                                ? null
                                : () => _changeMode(
                                  _resetEmail || _isSignUp
                                      ? _LoginMode.signIn
                                      : _LoginMode.signUp,
                                ),
                        child: Text(
                          _resetEmail
                              ? 'Back to sign in'
                              : _isSignUp
                              ? 'Have an account? Sign in'
                              : 'No account? Create one',
                        ),
                      ),
                    if (_newPassword && !savedPassword)
                      AppButton.text(
                        label: 'Cancel password reset',
                        onPressed:
                            _loading
                                ? null
                                : () async {
                                  setState(() => _loading = true);
                                  try {
                                    await SupabaseService.signOut();
                                  } catch (_) {
                                    if (mounted) {
                                      setState(
                                        () =>
                                            _error =
                                                'Could not sign out. Try again.',
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _loading = false);
                                    }
                                  }
                                },
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
    String label, {
    String? error,
    Widget? suffixIcon,
  }) => InputDecoration(
    labelText: label,
    errorText: error,
    errorMaxLines: 3,
    suffixIcon: suffixIcon,
    border: const OutlineInputBorder(borderRadius: AppRadius.field),
  );
}
