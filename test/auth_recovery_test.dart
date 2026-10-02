import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/auth/auth_gate.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/login_screen.dart';
import 'package:gymapp/services/supabase_service.dart';
import 'package:gymapp/services/adopt_local_data.dart';
import 'package:gymapp/theme/app_theme.dart';

import 'support/test_fonts.dart';
import 'support/hive_test_harness.dart';

void main() {
  final harness = HiveTestHarness();
  final requests = <http.Request>[];
  Completer<http.Response>? pending;
  bool rejectRequest = false;
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
        requests.add(request);
        if (pending != null) return pending!.future;
        if (rejectRequest) {
          return http.Response(jsonEncode({'msg': 'Try again later'}), 429);
        }
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
  setUp(() {
    requests.clear();
    pending = null;
    rejectRequest = false;
    user['id'] = 'user-1';
    SupabaseService.passwordRecoveryPending = false;
  });
  tearDown(() async {
    pending = null;
    rejectRequest = false;
    await SupabaseService.signOut();
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
    await harness.close();
  });

  Widget host(Widget child) => MaterialApp(
    theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
    home: child,
  );

  Widget gateHost({
    Widget home = const Scaffold(body: Text('Signed-in home')),
  }) {
    var navigatorKey = GlobalKey<NavigatorState>();
    return StatefulBuilder(
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
    );
  }

  Future<void> openRecovery(WidgetTester tester) async {
    await tester.pumpWidget(host(const LoginScreen()));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'reset request validates email, sends redirect, and announces result',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await openRecovery(tester);
      expect(find.widgetWithText(TextField, 'Password'), findsNothing);
      await tester.tap(find.text('Send reset email'));
      await tester.pump();
      expect(find.text('Enter your email.'), findsOneWidget);
      expect(requests, isEmpty);
      await tester.enterText(find.byType(TextField), ' person@example.com ');
      await tester.runAsync(() async {
        await tester.tap(find.text('Send reset email'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      final request = requests.single;
      expect(request.url.path, '/auth/v1/recover');
      expect(jsonDecode(request.body)['email'], 'person@example.com');
      expect(
        request.url.queryParameters['redirect_to'],
        SupabaseService.recoveryAppUrl,
      );
      final result = find.textContaining('If an account uses this email');
      expect(result, findsOneWidget);
      expect(
        tester
            .getSemantics(result)
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      semantics.dispose();
    },
  );

  testWidgets('invalid email keeps focus and errors clear after correction', (
    tester,
  ) async {
    await openRecovery(tester);
    await tester.enterText(find.byType(TextField), 'invalid');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    await tester.enterText(find.byType(TextField), 'valid@example.com');
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsNothing);
    expect(requests, isEmpty);
  });

  testWidgets(
    'reset email busy state guards duplicate requests and exposes errors',
    (tester) async {
      await openRecovery(tester);
      await tester.enterText(find.byType(TextField), 'person@example.com');
      pending = Completer<http.Response>();
      await tester.runAsync(() async {
        await tester.tap(find.text('Send reset email'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.bySemanticsLabel('Sending reset email'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        pending!.complete(
          http.Response(jsonEncode({'msg': 'Try again later'}), 429),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Try again later'), findsOneWidget);
      expect(requests, hasLength(1));
    },
  );

  testWidgets(
    'new password validates confirmation then reports success before continuing',
    (tester) async {
      var continued = false;
      // Recovery session from an incoming link; no real account or email needed.
      await SupabaseService.auth.getSessionFromUrl(
        Uri.parse(
          'io.opengym.app://reset-password/#access_token=test-token&refresh_token=refresh-token&expires_in=3600&token_type=bearer&type=recovery',
        ),
      );
      await tester.pumpWidget(
        host(
          LoginScreen(
            passwordRecovery: true,
            onPasswordRecovered: () => continued = true,
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'New password'),
        'new-password',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm password'),
        'different',
      );
      await tester.tap(find.text('Save password'));
      await tester.pump();
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Confirm password'),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm password'),
        'new-password',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Password updated.'), findsOneWidget);
      expect(continued, isFalse);
      final update = requests.singleWhere((r) => r.method == 'PUT');
      expect(jsonDecode(update.body)['password'], 'new-password');
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(continued, isTrue);
    },
  );

  testWidgets(
    'AuthGate catches a replayed recovery and keeps it through user updates',
    (tester) async {
      await SupabaseService.auth.getSessionFromUrl(
        Uri.parse(
          'io.opengym.app://reset-password/#access_token=test-token&refresh_token=refresh-token&expires_in=3600&token_type=bearer&type=recovery',
        ),
      );
      await tester.pumpWidget(gateHost());
      await tester.pump();
      expect(find.text('Choose a new password'), findsOneWidget);
      await SupabaseService.updatePassword('another-password');
      await tester.pump();
      expect(find.text('Choose a new password'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'link failures remain visible in a recovery form without discarding entry',
    (tester) async {
      await SupabaseService.auth.getSessionFromUrl(
        Uri.parse(
          'io.opengym.app://reset-password/#access_token=test-token&refresh_token=refresh-token&expires_in=3600&token_type=bearer&type=recovery',
        ),
      );
      await tester.pumpWidget(gateHost());
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'New password'),
        'typed-password',
      );
      // Simulate the SDK's app-link failure event, without sending a real link.
      // ignore: invalid_use_of_internal_member
      SupabaseService.auth.notifyException(
        const AuthException('Expired link'),
        StackTrace.current,
      );
      await tester.pump();
      expect(
        find.textContaining('Could not verify the sign-in or reset link'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'New password'))
            .controller!
            .text,
        'typed-password',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a second account recovery clears the first account password entry',
    (tester) async {
      final link = Uri.parse(
        'io.opengym.app://reset-password/#access_token=test-token&refresh_token=refresh-token&expires_in=3600&token_type=bearer&type=recovery',
      );
      await SupabaseService.auth.getSessionFromUrl(link);
      await tester.pumpWidget(gateHost());
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'New password'),
        'first-password',
      );
      user['id'] = 'user-2';
      await SupabaseService.auth.getSessionFromUrl(link);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'New password'))
            .controller!
            .text,
        isEmpty,
      );
      await tester.tap(find.text('Save password'));
      await tester.pump();
      expect(requests.where((request) => request.method == 'PUT'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a stale recovery form cannot update a changed account', (
    tester,
  ) async {
    final link = Uri.parse(
      'io.opengym.app://reset-password/#access_token=test-token&refresh_token=refresh-token&expires_in=3600&token_type=bearer&type=recovery',
    );
    await SupabaseService.auth.getSessionFromUrl(link);
    await tester.pumpWidget(host(const LoginScreen(passwordRecovery: true)));
    await tester.enterText(
      find.widgetWithText(TextField, 'New password'),
      'first-password',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'first-password',
    );
    user['id'] = 'user-2';
    await SupabaseService.auth.getSessionFromUrl(link);
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your account changed'), findsOneWidget);
    expect(requests.where((request) => request.method == 'PUT'), isEmpty);
  });

  testWidgets('recovery appears above a pushed route and restores its draft', (
    tester,
  ) async {
    await SupabaseService.auth.getSessionFromUrl(
      Uri.parse(
        'io.opengym.app://callback/#access_token=test-token&refresh_token=refresh-token&expires_in=3600&token_type=bearer&type=signup',
      ),
    );
    await tester.pumpWidget(gateHost());
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder:
            (_) => const Scaffold(
              body: TextField(
                decoration: InputDecoration(labelText: 'Workout draft'),
              ),
            ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Unsaved notes');
    await SupabaseService.auth.getSessionFromUrl(
      Uri.parse(
        'io.opengym.app://reset-password/#access_token=test-token&refresh_token=refresh-token&expires_in=3600&token_type=bearer&type=recovery',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(find.text('Workout draft'), findsNothing);
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
    await tester.pumpAndSettle();
    expect(find.text('Workout draft'), findsOneWidget);
    expect(find.text('Unsaved notes'), findsOneWidget);
    expect(
      identical(
        tester.state<NavigatorState>(find.byType(Navigator)),
        navigator,
      ),
      isTrue,
    );
  });

  testWidgets('another account recovery replaces the previous account navigator', (
    tester,
  ) async {
    await SupabaseService.auth.getSessionFromUrl(
      Uri.parse(
        'io.opengym.app://callback/#access_token=test-token&refresh_token=refresh-token&expires_in=3600&token_type=bearer&type=signup',
      ),
    );
    await tester.pumpWidget(gateHost());
    await tester.pumpAndSettle();
    final firstNavigator = tester.state<NavigatorState>(find.byType(Navigator));
    firstNavigator.push(
      MaterialPageRoute<void>(
        builder:
            (_) => const Scaffold(
              body: TextField(
                decoration: InputDecoration(labelText: 'Account A draft'),
              ),
            ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Account A unsaved notes');
    user['id'] = 'user-2';
    await SupabaseService.auth.getSessionFromUrl(
      Uri.parse(
        'io.opengym.app://reset-password/#access_token=second-token&refresh_token=refresh-token&expires_in=3600&token_type=bearer&type=recovery',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'New password'),
      'second-password',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'second-password',
    );
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Signed-in home'), findsOneWidget);
    expect(
      find.text('Account A unsaved notes', skipOffstage: false),
      findsNothing,
    );
    expect(
      identical(
        tester.state<NavigatorState>(find.byType(Navigator)),
        firstNavigator,
      ),
      isFalse,
    );
  });

  testWidgets('link failure banner preserves a pushed route and its draft', (
    tester,
  ) async {
    await SupabaseService.auth.getSessionFromUrl(
      Uri.parse(
        'io.opengym.app://callback/#access_token=test-token&refresh_token=refresh-token&expires_in=3600&token_type=bearer&type=signup',
      ),
    );
    await tester.pumpWidget(gateHost());
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder:
            (_) => const Scaffold(
              body: TextField(
                decoration: InputDecoration(labelText: 'Workout draft'),
              ),
            ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Unsaved notes');
    // ignore: invalid_use_of_internal_member
    SupabaseService.auth.notifyException(
      const AuthException('Expired link'),
      StackTrace.current,
    );
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsOneWidget);
    expect(find.text('Unsaved notes'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.text('Unsaved notes'), findsOneWidget);
    expect(
      identical(
        tester.state<NavigatorState>(find.byType(Navigator)),
        navigator,
      ),
      isTrue,
    );
  });

  testWidgets(
    'expired link failures are announced while the signed-in app remains available',
    (tester) async {
      await SupabaseService.auth.getSessionFromUrl(
        Uri.parse(
          'io.opengym.app://callback/#access_token=test-token&refresh_token=refresh-token&expires_in=3600&token_type=bearer&type=signup',
        ),
      );
      await tester.runAsync(() => AdoptLocalData.prepareLocal());
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SplitProvider()),
            ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
            ChangeNotifierProvider(create: (_) => WorkoutSessionProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider<UpdateProvider>(
              create: (_) => _QuietUpdates(),
            ),
          ],
          child: gateHost(home: const AuthenticatedHome()),
        ),
      );
      await tester.pumpAndSettle();
      // ignore: invalid_use_of_internal_member
      SupabaseService.auth.notifyException(
        const AuthException('Expired link'),
        StackTrace.current,
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('Could not verify the sign-in or reset link'),
        findsOneWidget,
      );
      expect(find.byType(MaterialBanner), findsOneWidget);
      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      expect(find.byType(MaterialBanner), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _QuietUpdates extends UpdateProvider {
  @override
  Future<void> checkOnStartup() async {}
}
