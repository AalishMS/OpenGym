import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/adopt_local_data.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../screens/login_screen.dart';
import '../app_shell.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // Offline-only build (no Supabase config): behave exactly like before.
    if (!SupabaseService.isConfigured) {
      return const AppShell();
    }
    return StreamBuilder<AuthState>(
      stream: SupabaseService.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = SupabaseService.auth.currentSession;
        if (session != null) {
          return const _PostLoginGate();
        }
        return const LoginScreen();
      },
    );
  }
}

/// Runs adoption once when a session is present, showing a loader until the
/// first clear/pull settles, then the app.
class _PostLoginGate extends StatefulWidget {
  const _PostLoginGate();

  @override
  State<_PostLoginGate> createState() => _PostLoginGateState();
}

class _PostLoginGateState extends State<_PostLoginGate> {
  late final Future<void> _ready = _adoptThenReload();

  Future<void> _adoptThenReload() async {
    await AdoptLocalData.run();
    if (!mounted) return;
    context.read<WorkoutPlanProvider>().loadPlans();
    context.read<WorkoutSessionProvider>().loadSessions();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F0F0F),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF00A8FF)),
            ),
          );
        }
        return const AppShell();
      },
    );
  }
}
