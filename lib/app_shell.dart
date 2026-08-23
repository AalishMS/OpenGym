import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/update_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/home_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/history_screen.dart';
import 'theme/breakpoints.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_nav_rail.dart';
import 'widgets/update_dialog.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Index into [_screens]. Dashboard is index 0 (desktop-only); the phone
  // bottom bar addresses screens 1–4.
  int _currentIndex = 0;

  /// Guards against a second prompt if this State is rebuilt.
  bool _updatePromptShown = false;

  final List<Widget> _screens = const [
    DashboardScreen(),
    HomeScreen(),
    HistoryScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Deliberately not awaited. The check runs after the first frame so it
    // cannot delay startup, and AppShell is the first widget that is past both
    // Hive init and the auth gate — so the prompt never lands on the splash or
    // the login screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    final updates = context.read<UpdateProvider>();
    await updates.checkOnStartup();
    if (!mounted || _updatePromptShown) return;
    if (!updates.isUpdateAvailable) return;
    _updatePromptShown = true;
    await showUpdateDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = Breakpoints.isWide(context);

    // Dashboard (index 0) is desktop-only. On the narrow bottom-bar layout it's
    // unreachable, so clamp the rendered/highlighted screen to Plans (index 1).
    // This is a render-time clamp — `_currentIndex` is left untouched so that
    // widening the window back returns the user to the Dashboard.
    final effectiveIndex =
        isWide ? _currentIndex : (_currentIndex == 0 ? 1 : _currentIndex);

    final stack = IndexedStack(index: effectiveIndex, children: _screens);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            AppNavRail(
              currentIndex: effectiveIndex,
              onTap: (i) => setState(() => _currentIndex = i),
            ),
            Expanded(child: stack),
          ],
        ),
      );
    }

    return Scaffold(
      body: stack,
      bottomNavigationBar: AppBottomNav(
        // Bottom bar slots [PLANS, HISTORY, STATS, SETTINGS] map to screens 1–4.
        currentIndex: (effectiveIndex - 1).clamp(0, 3),
        onTap: (i) => setState(() => _currentIndex = i + 1),
      ),
    );
  }
}
