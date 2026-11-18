import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'auth_error_message.dart';
import 'data_preparation_failure.dart';
import '../services/training_block_migration.dart';
import '../services/adopt_local_data.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../providers/split_provider.dart';
import '../screens/login_screen.dart';
import '../app_shell.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../widgets/floating_notice.dart';

const String _kOfflineTitle = "You're offline";
const String _kOfflineDetail =
    'Your workouts are saved on this device and will sync when you reconnect.';

/// How long the offline notice stays before it leaves on its own. Closing it
/// either way starts the same cooldown, so a retrying token refresh can't keep
/// bringing it back.
const Duration kOfflineNoticeDuration = Duration(seconds: 6);

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
          // retried automatically and the next auth event clears the notice.
          _authError =
              offline
                  ? '$_kOfflineTitle. $_kOfflineDetail'
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

  /// Every gate message is a headline sentence followed by advice; the notice
  /// shows the headline as its title and the advice beneath it.
  Widget _buildNotice(String message) {
    final split = message.indexOf('. ');
    final title = split < 0 ? message : message.substring(0, split);
    final detail = split < 0 ? null : message.substring(split + 2);
    return FloatingNotice(
      key: ValueKey(message),
      icon:
          _authErrorIsOffline ? LucideIcons.cloudOff : LucideIcons.circleAlert,
      title: title,
      detail: detail,
      isError: !_authErrorIsOffline,
      // Being offline is information, not a problem to solve, so it leaves on
      // its own. A failed link or server error waits to be read.
      autoDismissAfter: _authErrorIsOffline ? kOfflineNoticeDuration : null,
      // An outgoing notice is still mounted while it animates away; its timer
      // or a late swipe must not close the message that replaced it.
      onDismiss: () {
        if (_authError == message) _dismissAuthError();
      },
    );
  }

  // The page colour under every surface, so one arriving fades in from the
  // page rather than from black.
  @override
  Widget build(BuildContext context) => Overlay.wrap(
    child: ColoredBox(
      color: backgroundColor(context),
      child: _buildContent(context),
    ),
  );

  Widget _buildContent(BuildContext context) {
    // Offline-only build (no Supabase config): behave exactly like before.
    if (!SupabaseService.isConfigured) {
      return widget.child;
    }
    // Wait for the SDK's replayed event before preparing account data. A
    // recovered session may already exist when this widget is first mounted.
    if (!_authStateReady) {
      return const Scaffold(
        body: Center(child: _PatientProgress(label: 'Checking sign-in')),
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
              // The app arrives through AuthenticatedHome; this only fades it
              // back in when a finished password recovery uncovers it.
              child: _ArrivalFade(
                initial: false,
                shown: !recovering,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    KeyedSubtree(
                      key: const ValueKey('signed-in-content'),
                      child: widget.child,
                    ),
                    // Floats over the app rather than pushing every screen
                    // down.
                    FloatingNoticeHost(
                      notice:
                          _authError != null && !recovering
                              ? _buildNotice(_authError!)
                              : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (recovering)
            _ArrivalFade(
              key: ValueKey('password-recovery:${session.user.id}'),
              child: LoginScreen(
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
            ),
        ],
      );
    }
    return _ArrivalFade(
      key: const ValueKey('login'),
      child: LoginScreen(key: ValueKey(_authError), initialError: _authError),
    );
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
  late Future<void> _ready = _prepare();

  Future<void> _prepare() async {
    await AdoptLocalData.prepareLocal();
    if (!mounted) return;
    context.read<SplitProvider>().loadSplits();
    context.read<WorkoutPlanProvider>().loadPlans();
    context.read<WorkoutSessionProvider>().loadSessions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(AdoptLocalData.syncInBackground());
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: backgroundColor(context),
            body: const Center(
              child: _PatientProgress(
                label: 'Loading your data',
                value: 'In progress',
              ),
            ),
          );
        }
        if (snap.hasError) {
          final error = snap.error;
          return _ArrivalFade(
            key: const ValueKey('preparation-failed'),
            child: DataPreparationFailure(
              onRetry: () async {
                setState(() => _ready = _prepare());
              },
              onExport:
                  () => exportTrainingSafetyCopy(
                    error is TrainingPreparationException
                        ? error.safetySnapshotPath
                        : null,
                  ),
            ),
          );
        }
        return const _ArrivalFade(key: ValueKey('app'), child: AppShell());
      },
    );
  }
}

/// How long a spinner waits before it shows. Signing in is checked from the
/// device and account data is prepared locally, so both usually finish within
/// a frame or two; a spinner that appears and vanishes at once only flickers.
/// Past this, the wait is real and the spinner fades in to say so.
const Duration _kProgressGrace = Duration(milliseconds: 400);

/// A progress indicator for a wait that is usually too short to see: the page
/// stays bare for [_kProgressGrace], then the spinner fades in over
/// [AppMotion.quick]. Screen readers hear [label] from the first frame, and
/// finders find it, as before; only what is painted waits. Under reduced
/// motion it still waits, then appears without the fade.
class _PatientProgress extends StatefulWidget {
  final String label;
  final String? value;

  const _PatientProgress({required this.label, this.value});

  @override
  State<_PatientProgress> createState() => _PatientProgressState();
}

class _PatientProgressState extends State<_PatientProgress>
    with SingleTickerProviderStateMixin {
  static final Duration _total = _kProgressGrace + AppMotion.quick;
  static final double _start =
      _kProgressGrace.inMicroseconds / _total.inMicroseconds;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
  );
  Animation<double>? _opacity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opacity != null) return;
    _opacity = CurvedAnimation(
      parent: _controller,
      curve:
          MediaQuery.disableAnimationsOf(context)
              ? Threshold(_start)
              : Interval(_start, 1, curve: AppMotion.curve),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      value: widget.value,
      liveRegion: true,
      child: FadeTransition(
        opacity: _opacity!,
        alwaysIncludeSemantics: true,
        child: const CircularProgressIndicator(),
      ),
    );
  }
}

/// Fades a surface in from the page over [AppMotion.quick] where it takes
/// the place of another: the login screen, the app after its data is ready,
/// password recovery. What it replaces is gone at once, never kept alive
/// beside it: on an account change that would be the previous account's
/// app, its routes and its focus. So a swap reads as the new surface
/// arriving on the page colour.
///
/// It plays once per State when [initial] is set, and again whenever [shown]
/// turns true, for a surface uncovered after being hidden. The surface is laid
/// out, tappable and announced from its first frame. Under reduced motion it
/// simply appears.
class _ArrivalFade extends StatefulWidget {
  final bool initial;
  final bool shown;
  final Widget child;

  const _ArrivalFade({
    super.key,
    this.initial = true,
    this.shown = true,
    required this.child,
  });

  @override
  State<_ArrivalFade> createState() => _ArrivalFadeState();
}

class _ArrivalFadeState extends State<_ArrivalFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.quick,
    value: 1,
  );
  late final CurvedAnimation _opacity = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.curve,
  );
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (widget.initial && widget.shown) _play();
  }

  @override
  void didUpdateWidget(_ArrivalFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shown && !oldWidget.shown) _play();
  }

  void _play() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _opacity.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    alwaysIncludeSemantics: true,
    child: widget.child,
  );
}
