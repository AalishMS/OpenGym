import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/screens/login_screen.dart';
import 'package:gymapp/theme/app_theme.dart';

void main() {
  Completer<http.Response>? pendingAuth;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient((_) {
        final pending = pendingAuth;
        if (pending != null) return pending.future;
        return Future.value(http.Response('{}', 400));
      }),
    );
  });

  setUp(() => pendingAuth = null);

  Widget loginHost() => MaterialApp(
    theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
    home: const LoginScreen(),
  );

  testWidgets('empty submission reports the required-fields error', (
    tester,
  ) async {
    await tester.pumpWidget(loginHost());
    await tester.tap(find.text('[SIGN IN]'));
    await tester.pump();
    expect(find.text('Email and password required.'), findsOneWidget);
  });

  testWidgets('mode switch updates heading and primary action', (tester) async {
    await tester.pumpWidget(loginHost());
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('[SIGN IN]'), findsOneWidget);
    await tester.tap(find.text('No account? Create one'));
    await tester.pump();
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('[CREATE ACCOUNT]'), findsOneWidget);
  });

  testWidgets('credentials expose autofill and suitable input types', (
    tester,
  ) async {
    await tester.pumpWidget(loginHost());
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields, hasLength(2));
    expect(fields[0].autofillHints, contains(AutofillHints.email));
    expect(fields[0].keyboardType, TextInputType.emailAddress);
    expect(fields[1].autofillHints, contains(AutofillHints.password));
    expect(fields[1].keyboardType, TextInputType.visiblePassword);
    await tester.tap(find.text('No account? Create one'));
    await tester.pump();
    expect(
      tester.widgetList<TextField>(find.byType(TextField)).last.autofillHints,
      contains(AutofillHints.newPassword),
    );
  });

  testWidgets('password visibility can be toggled', (tester) async {
    await tester.pumpWidget(loginHost());
    TextField password() =>
        tester.widgetList<TextField>(find.byType(TextField)).last;
    expect(password().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(password().obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('loading disables submission and mode switching', (tester) async {
    pendingAuth = Completer<http.Response>();
    await tester.pumpWidget(loginHost());
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'person@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password123',
    );
    await tester.tap(find.text('[SIGN IN]'));
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final semantics = tester.ensureSemantics();
    final loadingSemantics = tester.getSemantics(
      find.bySemanticsLabel('Signing in'),
    );
    expect(
      loadingSemantics,
      matchesSemantics(
        label: 'Signing in',
        value: 'In progress',
        isLiveRegion: true,
        isButton: true,
        isFocusable: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    semantics.dispose();
    pendingAuth!.complete(http.Response('{}', 400));
    await tester.pump();
  });

  testWidgets('loading spinner uses the button foreground', (tester) async {
    pendingAuth = Completer<http.Response>();
    await tester.pumpWidget(loginHost());
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'person@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password123',
    );
    await tester.tap(find.text('[SIGN IN]'));
    await tester.pump();

    final spinner = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(
      spinner.color,
      onAccentColor(tester.element(find.byType(LoginScreen))),
    );

    pendingAuth!.complete(http.Response('{}', 400));
    await tester.pump();
  });

  testWidgets('mode switch and password visibility targets are at least 48', (
    tester,
  ) async {
    await tester.pumpWidget(loginHost());
    for (final finder in [
      find.widgetWithText(TextButton, 'No account? Create one'),
      find.byTooltip('Show password'),
    ]) {
      final size = tester.getSize(finder);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });
}
