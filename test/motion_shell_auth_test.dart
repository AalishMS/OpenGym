import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/app_shell.dart';
import 'package:gymapp/auth/auth_gate.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/login_screen.dart';
import 'package:gymapp/services/adopt_local_data.dart';
import 'package:gymapp/services/supabase_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/motion.dart';

import 'support/hive_test_harness.dart';
import 'support/test_fonts.dart';

const _signUpLink =
    'io.opengym.app://callback/#access_token=test-token&refresh_token=refresh-token&expires_in=3600&token_type=bearer&type=signup';
const _recoveryLink =
    'io.opengym.app://reset-password/#access_token=test-token&refresh_token=refresh-token&expires_in=3600&token_type=bearer&type=recovery';

void main() {
  final harness = HiveTestHarness();
  final user = {
    'id': 'user-1',
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'person@example.com',
    'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
  };

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/user')) {
          return http.Response(jsonEncode(user), 200);
        }
        if (request.url.path.startsWith('/rest/')) {
          return http.Response('[]', 200);
        }
        return http.Response('{}', 200);
      }),
    );
    await harness.open(includeSplits: true);
  });
  setUp(() => SupabaseService.passwordRecoveryPending = false);
  tearDown(() async => SupabaseService.signOut());
  tearDownAll(() async {
    await Supabase.instance.dispose();
    await harness.close();
  });

  Widget gateHost({
    Widget home = const Scaffold(body: Text('Signed-in home')),
    bool reduceMotion = false,
  }) {
    var navigatorKey = GlobalKey<NavigatorState>();
    return MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 800),
        disableAnimations: reduceMotion,
      ),
      child: StatefulBuilder(
        builder:
            (context, setHostState) => MaterialApp(
              navigatorKey: navigatorKey,
              theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
              builder:
                  (context, navigator) => AuthGate(
                    child: navigator!,
                    onAccountChanged:
                        (_) => setHostState(
                          () => navigatorKey = GlobalKey<NavigatorState>(),
                        ),
                  ),
              home: home,
            ),
      ),
    );
  }

  /// The opacity the nearest fade above [finder] paints it at.
  double fadeOf(WidgetTester tester, Finder finder) =>
      tester
          .widget<FadeTransition>(
            find
                .ancestor(of: finder, matching: find.byType(FadeTransition))
                .first,
          )
          .opacity
          .value;

  Finder spinner(String label) => find.descendant(
    of: find.bySemanticsLabel(label),
    matching: find.byType(CircularProgressIndicator),
  );

  testWidgets('the sign-in check paints no spinner for a wait it does not '
      'need, and login fades in on the page', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(gateHost());
    // Announced and findable from its first frame, but not yet painted.
    expect(find.semantics.byLabel('Checking sign-in'), findsOne);
    expect(fadeOf(tester, spinner('Checking sign-in')), 0);

    // The replayed auth event lands within a frame or two.
    await tester.pump();
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Checking sign-in'), findsNothing);
    // Arriving: tappable and announced at once, painted rising from the page.
    expect(fadeOf(tester, find.byType(LoginScreen)), lessThan(1));
    expect(find.semantics.byLabel('Sign in'), findsWidgets);
    await tester.pump(AppMotion.quick);
    expect(fadeOf(tester, find.byType(LoginScreen)), 1);
    // A rebuild, such as a new error, does not replay the arrival.
    await tester.tap(find.text('No account? Create one'));
    await tester.pump();
    expect(fadeOf(tester, find.byType(LoginScreen)), 1);
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('signing in removes the login screen at once', (tester) async {
    await tester.pumpWidget(gateHost());
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await SupabaseService.auth.getSessionFromUrl(Uri.parse(_signUpLink));
    for (
      var i = 0;
      i < 10 && find.text('Signed-in home').evaluate().isEmpty;
      i++
    ) {
      await tester.pump();
    }
    // On the frame the app arrives, the outgoing login, with its fields and focus, is not kept alive
    // beside the app while it arrives.
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Signed-in home'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('signing out removes the previous account at once', (
    tester,
  ) async {
    await SupabaseService.auth.getSessionFromUrl(Uri.parse(_signUpLink));
    await tester.pumpWidget(gateHost());
    await tester.pumpAndSettle();
    expect(find.text('Signed-in home'), findsOneWidget);

    // Signing out awaits real work, so it runs outside fake time.
    await tester.runAsync(SupabaseService.signOut);
    for (
      var i = 0;
      i < 10 && find.byType(LoginScreen).evaluate().isEmpty;
      i++
    ) {
      await tester.pump();
    }
    expect(find.text('Signed-in home', skipOffstage: false), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(fadeOf(tester, find.byType(LoginScreen)), lessThan(1));
    await tester.pumpAndSettle();
    expect(fadeOf(tester, find.byType(LoginScreen)), 1);
  });

  testWidgets('password recovery fades in, and the app fades back after', (
    tester,
  ) async {
    await SupabaseService.auth.getSessionFromUrl(Uri.parse(_signUpLink));
    await tester.pumpWidget(gateHost());
    await tester.pumpAndSettle();
    // The gate's own fade sits above the navigator, outside any route's
    // transition.
    final app = find.byKey(
      const ValueKey('signed-in-content'),
      skipOffstage: false,
    );
    expect(fadeOf(tester, app), 1);

    await SupabaseService.auth.getSessionFromUrl(Uri.parse(_recoveryLink));
    for (
      var i = 0;
      i < 10 && find.byType(LoginScreen).evaluate().isEmpty;
      i++
    ) {
      await tester.pump();
    }
    final recovery = find.byType(LoginScreen);
    expect(recovery, findsOneWidget);
    // The app is hidden at once rather than crossing under the form.
    expect(find.text('Signed-in home'), findsNothing);
    expect(fadeOf(tester, recovery), lessThan(1));
    await tester.pumpAndSettle();
    expect(fadeOf(tester, recovery), 1);

    await tester.enterText(
      find.widgetWithText(TextField, 'New password'),
      'new-password',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'new-password',
    );
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('Signed-in home'), findsOneWidget);
    expect(fadeOf(tester, app), lessThan(1));
    await tester.pumpAndSettle();
    expect(fadeOf(tester, app), 1);
  });

  testWidgets('surfaces arrive at once under reduced motion', (tester) async {
    await tester.pumpWidget(gateHost(reduceMotion: true));
    await tester.pump();
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(fadeOf(tester, find.byType(LoginScreen)), 1);
    await tester.pumpAndSettle();
  });

  group('preparing account data', () {
    Widget appHost({bool reduceMotion = false}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SplitProvider()),
        ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
        ChangeNotifierProvider(create: (_) => WorkoutSessionProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider<UpdateProvider>(create: (_) => _QuietUpdates()),
      ],
      child: gateHost(
        home: const AuthenticatedHome(),
        reduceMotion: reduceMotion,
      ),
    );

    testWidgets('the app fades in once its data is ready', (tester) async {
      await SupabaseService.auth.getSessionFromUrl(Uri.parse(_signUpLink));
      // Hive writes started under fake time leave the boxes unable to close,
      // so the first preparation runs for real; the gate's own is then quick.
      await tester.runAsync(AdoptLocalData.prepareLocal);
      await tester.pumpWidget(appHost());
      for (var i = 0; i < 50 && find.byType(AppShell).evaluate().isEmpty; i++) {
        // While local preparation runs, the spinner is not painted yet.
        final loading = spinner('Loading your data');
        if (loading.evaluate().isNotEmpty) {
          expect(fadeOf(tester, loading), 0);
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      expect(find.byType(AppShell), findsOneWidget);
      expect(spinner('Loading your data'), findsNothing);
      expect(fadeOf(tester, find.byType(AppShell)), lessThan(1));
      await tester.pump(AppMotion.quick);
      expect(fadeOf(tester, find.byType(AppShell)), 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

class _QuietUpdates extends UpdateProvider {
  @override
  Future<void> checkOnStartup() async {}
}
