import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/workout_plan_provider.dart';
import 'providers/workout_session_provider.dart';
import 'providers/progression_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/update_provider.dart';
import 'providers/split_provider.dart';
import 'services/hive_service.dart';
import 'services/supabase_service.dart';
import 'services/sync_service.dart';
import 'auth/auth_gate.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await HiveService.init();
    await SupabaseService.init();
  } catch (e) {
    debugPrint('Hive init error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _initialized = false;
  late WorkoutPlanProvider _workoutPlanProvider;
  late WorkoutSessionProvider _workoutSessionProvider;
  late ProgressionProvider _progressionProvider;
  late SettingsProvider _settingsProvider;
  late SplitProvider _splitProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    SyncService.instance.syncNow(); // initial cycle if already logged in
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

  Future<void> _initialize() async {
    _splitProvider = SplitProvider();
    _workoutPlanProvider = WorkoutPlanProvider(_splitProvider);
    _workoutSessionProvider = WorkoutSessionProvider(_splitProvider);
    _progressionProvider = ProgressionProvider(_splitProvider);
    _settingsProvider = SettingsProvider();

    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      setState(() {
        _initialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(
          SettingsProvider.accents[SettingsProvider.defaultAccentIndex].seed,
          Brightness.light,
        ),
        home: Builder(
          builder:
              (context) => Scaffold(
                backgroundColor: backgroundColor(context),
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '> OPENGYM',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: accentColor(context),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Semantics(
                        label: 'Starting OpenGym',
                        value: 'In progress',
                        liveRegion: true,
                        child: const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _splitProvider),
        ChangeNotifierProvider.value(value: _workoutPlanProvider),
        ChangeNotifierProvider.value(value: _workoutSessionProvider),
        ChangeNotifierProvider.value(value: _progressionProvider),
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
            title: 'OpenGym',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(seed, Brightness.light),
            darkTheme: buildTheme(seed, Brightness.dark),
            themeMode: settings.themeMode,
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}
