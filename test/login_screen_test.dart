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

  testWidgets('empty submission reports field errors and focuses email', (
    tester,
  ) async {
    await tester.pumpWidget(loginHost());
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter your email.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].decoration?.errorText, 'Enter your email.');
    expect(fields[1].decoration?.errorText, 'Enter your password.');
    expect(fields[0].focusNode?.hasFocus, isTrue);
  });

  testWidgets('mode switch updates heading and primary action', (tester) async {
    await tester.pumpWidget(loginHost());
    expect(find.text('Sign in'), findsWidgets);
    expect(find.widgetWithText(ElevatedButton, 'Sign in'), findsOneWidget);
    await tester.tap(find.text('No account? Create one'));
    await tester.pump();
    expect(find.text('Create account'), findsWidgets);
    expect(
      find.widgetWithText(ElevatedButton, 'Create account'),
      findsOneWidget,
    );
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
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(
      tester
          .widgetList<TextButton>(find.byType(TextButton))
          .every((button) => button.onPressed == null),
      isTrue,
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

  testWidgets('signing in without a connection says the device is offline', (
    tester,
  ) async {
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
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump();
    pendingAuth!.completeError(
      http.ClientException(
        "SocketException: Failed host lookup: 'example.supabase.co'",
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.text("You're offline. Check your connection and try again."),
      findsOneWidget,
    );
    expect(find.textContaining('SocketException'), findsNothing);
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
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
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
