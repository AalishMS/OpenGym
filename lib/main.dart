import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/workout_plan_provider.dart';
import 'providers/workout_session_provider.dart';
import 'providers/progression_provider.dart';
import 'providers/settings_provider.dart';
import 'services/hive_service.dart';
import 'app_shell.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await HiveService.init();
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

class _MyAppState extends State<MyApp> {
  bool _initialized = false;
  late WorkoutPlanProvider _workoutPlanProvider;
  late WorkoutSessionProvider _workoutSessionProvider;
  late ProgressionProvider _progressionProvider;
  late SettingsProvider _settingsProvider;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _workoutPlanProvider = WorkoutPlanProvider();
    _workoutSessionProvider = WorkoutSessionProvider();
    _progressionProvider = ProgressionProvider();
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
        home: Scaffold(
          backgroundColor: const Color(0xFF0F0F0F),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '> OPENGYM',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF00A8FF),
                  ),
                ),
                const SizedBox(height: 32),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF00A8FF),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _workoutPlanProvider),
        ChangeNotifierProvider.value(value: _workoutSessionProvider),
        ChangeNotifierProvider.value(value: _progressionProvider),
        ChangeNotifierProvider.value(value: _settingsProvider),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          final accentDark = settings.accentColorDark;
          final accentLight = settings.accentColorLight;

          return MaterialApp(
            title: 'OpenGym',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(accentLight, Brightness.light),
            darkTheme: buildTheme(accentDark, Brightness.dark),
            themeMode: settings.themeMode,
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
