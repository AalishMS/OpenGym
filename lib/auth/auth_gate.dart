import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'auth_error_message.dart';
import '../services/adopt_local_data.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../providers/split_provider.dart';
import '../screens/login_screen.dart';
import '../app_shell.dart';
import '../theme/app_theme.dart';

class AuthGate extends StatefulWidget {
  /// Wrap the app Navigator so incoming recovery is visible above pushed routes.
  final Widget child;
  final ValueChanged<String?> onAccountChanged;

  const AuthGate({
    required this.child,
    required this.onAccountChanged,
    super.key,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _subscription;
  bool _recoveringPassword = SupabaseService.passwordRecoveryPending;
  String? _recoveryUserId =
      SupabaseService.passwordRecoveryPending
          ? SupabaseService.auth.currentSession?.user.id
          : null;
  bool _requestingPasswordReset =
      kIsWeb && Uri.base.queryParameters['reset_password'] == 'true';
  bool _authStateReady = false;
  String? _authError;
  bool _authErrorIsOffline = false;
  Timer? _offlineNoticeCooldown;
  String? _presentedUserId = SupabaseService.currentUserId;

  @override
  void initState() {
    super.initState();
    if (!SupabaseService.isConfigured) return;
    _subscription = SupabaseService.auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        final userId = state.session?.user.id;
        if (userId != _presentedUserId) {
          _offlineNoticeCooldown?.cancel();
          _offlineNoticeCooldown = null;
          _presentedUserId = userId;
          widget.onAccountChanged(userId);
        }
        setState(() {
          _authStateReady = true;
          _authError = null;
          _authErrorIsOffline = false;
          if (state.event == AuthChangeEvent.passwordRecovery) {
            _requestingPasswordReset = false;
            _recoveringPassword = true;
            _recoveryUserId = state.session?.user.id;
            SupabaseService.passwordRecoveryPending = true;
          } else if (state.event == AuthChangeEvent.signedOut ||
              (_recoveringPassword &&
                  state.session?.user.id != _recoveryUserId)) {
            _recoveringPassword = false;
            _recoveryUserId = null;
            SupabaseService.passwordRecoveryPending = false;
          } else if (state.event == AuthChangeEvent.signedIn) {
            _requestingPasswordReset = false;
          }
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _authStateReady = true;
          final offline = isNetworkError(error);
          // Refresh retries must respect dismissal, even across successful auth
          // events. Only a new account or the cooldown expiry resets it.
          if (offline && _offlineNoticeCooldown != null) return;
          _authErrorIsOffline = offline;
          // A background token refresh with no network lands here too; it is
          // retried automatically and the next auth event clears the banner.
          _authError =
              offline
                  ? "You're offline. Your workouts are saved on this device and will sync when you reconnect."
                  : error is AuthRetryableFetchException
                  ? kServerUnavailableMessage
                  : 'Could not verify the sign-in or reset link. Request a new link and try again.';
        });
      },
    );
  }

  @override
  void dispose() {
    _offlineNoticeCooldown?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  void _dismissAuthError() {
    setState(() {
      if (_authErrorIsOffline) {
        _offlineNoticeCooldown?.cancel();
        _offlineNoticeCooldown = Timer(const Duration(minutes: 30), () {
          _offlineNoticeCooldown = null;
        });
      }
      _authError = null;
      _authErrorIsOffline = false;
    });
  }

  @override
  Widget build(BuildContext context) =>
      Overlay.wrap(child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    // Offline-only build (no Supabase config): behave exactly like before.
    if (!SupabaseService.isConfigured) {
      return widget.child;
    }
    // Wait for the SDK's replayed event before preparing account data. A
    // recovered session may already exist when this widget is first mounted.
    if (!_authStateReady) {
      return Scaffold(
        body: Center(
          child: Semantics(
            label: 'Checking sign-in',
            liveRegion: true,
            child: const CircularProgressIndicator(),
          ),
        ),
      );
    }
    final session = SupabaseService.auth.currentSession;
    if (session != null && !_requestingPasswordReset) {
      final recovering =
          _recoveringPassword && session.user.id == _recoveryUserId;
      return Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: recovering,
            child: Focus(
              descendantsAreFocusable: !recovering,
              descendantsAreTraversable: !recovering,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_authError != null && !recovering)
                    SafeArea(
                      bottom: false,
                      child: MaterialBanner(
                        backgroundColor: surfaceColor(context),
                        content: Semantics(
                          liveRegion: true,
                          child: Text(_authError!),
                        ),
                        actions: [
                          TextButton(
                            onPressed: _dismissAuthError,
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    key: const ValueKey('signed-in-content'),
                    child: widget.child,
                  ),
                ],
              ),
            ),
          ),
          if (recovering)
            LoginScreen(
              key: ValueKey('password-recovery:${session.user.id}'),
              passwordRecovery: true,
              initialError: _authError,
              onPasswordRecovered:
                  () => setState(() {
                    _recoveringPassword = false;
                    _recoveryUserId = null;
                    _authError = null;
                    SupabaseService.passwordRecoveryPending = false;
                  }),
            ),
        ],
      );
    }
    return LoginScreen(key: ValueKey(_authError), initialError: _authError);
  }
}

/// Exposes cached data after network-free account preparation, then reconciles
/// with the server in the background.
class AuthenticatedHome extends StatefulWidget {
  const AuthenticatedHome({super.key});

  @override
  State<AuthenticatedHome> createState() => _AuthenticatedHomeState();
}

class _AuthenticatedHomeState extends State<AuthenticatedHome> {
  late final bool _wasPrepared = AdoptLocalData.isPreparedForCurrentUser;
  late final Future<void> _ready = AdoptLocalData.prepareLocal();

  @override
  void initState() {
    super.initState();
    _ready.then((_) {
      if (!mounted) return;
      context.read<SplitProvider>().loadSplits();
      context.read<WorkoutPlanProvider>().loadPlans();
      context.read<WorkoutSessionProvider>().loadSessions();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(AdoptLocalData.syncInBackground());
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_wasPrepared) return const AppShell();

    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: backgroundColor(context),
            body: Center(
              child: Semantics(
                label: 'Loading your data',
                value: 'In progress',
                liveRegion: true,
                child: const CircularProgressIndicator(),
              ),
            ),
          );
        }
        return const AppShell();
      },
    );
  }
}
