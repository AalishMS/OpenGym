import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth/auth_gate.dart';
import 'providers/workout_plan_provider.dart';
import 'providers/workout_session_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/update_provider.dart';
import 'providers/split_provider.dart';
import 'services/hive_service.dart';
import 'services/adopt_local_data.dart';
import 'services/supabase_service.dart';
import 'services/sync_service.dart';
import 'services/tutorial_preferences.dart';
import 'screens/intro_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool showIntro = false;
  try {
    showIntro = await loadIntroPending();
    await Future.wait([HiveService.init(), SupabaseService.init()]);
    await AdoptLocalData.prepareLocal();
  } catch (e) {
    debugPrint('Local startup error: $e');
  }

  runApp(MyApp(showIntro: showIntro));
}

/// Decide before Hive's startup migration marks a fresh installation as old.
Future<bool> loadIntroPending() async {
  return TutorialPreferences.loadIntroPending();
}

class MyApp extends StatefulWidget {
  final bool showIntro;

  const MyApp({this.showIntro = false, super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late WorkoutPlanProvider _workoutPlanProvider;
  late WorkoutSessionProvider _workoutSessionProvider;
  late SettingsProvider _settingsProvider;
  late SplitProvider _splitProvider;
  late bool _showIntro;
  GlobalKey<NavigatorState> _accountNavigatorKey = GlobalKey<NavigatorState>();
  String? _navigatorUserId = SupabaseService.currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _showIntro = widget.showIntro;
    _splitProvider = SplitProvider();
    _workoutPlanProvider = WorkoutPlanProvider(_splitProvider);
    _workoutSessionProvider = WorkoutSessionProvider(_splitProvider);
    _settingsProvider = SettingsProvider();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SyncService.instance.syncNow();
    }
  }

  Future<void> _finishIntro({bool skipTutorial = false}) async {
    await TutorialPreferences.finishIntro(skipTutorial: skipTutorial);
    if (mounted) setState(() => _showIntro = false);
  }

  void _onAccountChanged(String? userId) {
    if (!mounted || userId == _navigatorUserId) return;
    setState(() {
      _navigatorUserId = userId;
      _accountNavigatorKey = GlobalKey<NavigatorState>();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _splitProvider),
        ChangeNotifierProvider.value(value: _workoutPlanProvider),
        ChangeNotifierProvider.value(value: _workoutSessionProvider),
        ChangeNotifierProvider.value(value: _settingsProvider),
        // Created here rather than in _initialize because it holds no state
        // that has to exist before the first frame — the check itself is
        // kicked off by AppShell once the UI is up.
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          // One seed, both themes. Each `buildTheme` call solves the seed into
          // roles against its own brightness's ground, which is what makes light
          // mode a real theme rather than the dark palette on a pale page.
          final seed = settings.accentSeed;

          return MaterialApp(
            navigatorKey: _accountNavigatorKey,
            title: 'OpenGym',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(seed, Brightness.light),
            darkTheme: buildTheme(seed, Brightness.dark),
            themeMode: settings.themeMode,
            builder:
                (context, navigator) =>
                    _showIntro
                        ? navigator!
                        : AuthGate(
                          onAccountChanged: _onAccountChanged,
                          child: navigator!,
                        ),
            home:
                _showIntro
                    ? IntroScreen(
                      onFinish: _finishIntro,
                      onSkip: () => _finishIntro(skipTutorial: true),
                    )
                    : const AuthenticatedHome(),
          );
        },
      ),
    );
  }
}
