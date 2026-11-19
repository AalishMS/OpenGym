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
import 'package:gymapp/theme/motion.dart';
import 'package:gymapp/widgets/motion/collapsible.dart';

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

  Widget loginHost({bool reduceMotion = false}) => MaterialApp(
    theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 800),
        disableAnimations: reduceMotion,
      ),
      child: const LoginScreen(),
    ),
  );

  final password = find.widgetWithText(TextField, 'Password');
  Finder regionOf(Finder finder) =>
      find.ancestor(of: finder, matching: find.byType(Collapsible)).first;

  testWidgets('a field leaving with the mode folds away and gives up focus', (
    tester,
  ) async {
    await tester.pumpWidget(loginHost());
    final full = tester.getSize(regionOf(password)).height;
    await tester.showKeyboard(password);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    // Still there while it folds, but it no longer holds focus or the
    // keyboard's input, and taps pass through it.
    expect(password, findsOneWidget);
    final field = tester.widget<TextField>(password);
    expect(field.focusNode!.hasFocus, isFalse);
    expect(
      find.ancestor(
        of: password,
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      ),
      findsWidgets,
    );
    // Email takes focus, as before.
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Email'))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.pump(AppMotion.standard ~/ 2);
    expect(
      tester.getSize(regionOf(password)).height,
      inExclusiveRange(0, full),
    );
    await tester.pumpAndSettle();
    expect(password, findsNothing);
    expect(find.byType(TextField), findsOneWidget);

    // Coming back, it opens from the top and is usable from its first frame.
    await tester.tap(find.text('Back to sign in'));
    await tester.pump();
    expect(password, findsOneWidget);
    await tester.pump(AppMotion.standard ~/ 2);
    expect(
      tester.getSize(regionOf(password)).height,
      inExclusiveRange(0, full),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(regionOf(password)).height, full);
    await tester.enterText(password, 'secret');
    expect(find.text('secret'), findsOneWidget);
  });

  testWidgets('the heading and button label cross to the new mode', (
    tester,
  ) async {
    await tester.pumpWidget(loginHost());
    await tester.tap(find.text('No account? Create one'));
    await tester.pump();
    // Both states are present for a moment; the new one is announced and
    // findable at once, the old one takes no taps.
    expect(find.text('Sync your training across devices.'), findsOneWidget);
    expect(
      find.text('Continue with your saved plans and history.'),
      findsOneWidget,
    );
    expect(find.text('Have an account? Sign in'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(
      find.text('Continue with your saved plans and history.'),
      findsNothing,
    );
    expect(find.text('No account? Create one'), findsNothing);
    expect(
      find.widgetWithText(ElevatedButton, 'Create account'),
      findsOneWidget,
    );
  });

  testWidgets('an error opens as a region and folds away on the next try', (
    tester,
  ) async {
    pendingAuth = Completer<http.Response>();
    await tester.pumpWidget(loginHost());
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'person@example.com',
    );
    await tester.enterText(password, 'password123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump();
    // The button's label crosses to progress.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pendingAuth!.completeError(
      http.ClientException("SocketException: Failed host lookup: 'x'"),
    );
    await tester.pump();
    await tester.pump();
    final error = find.text(
      "You're offline. Check your connection and try again.",
    );
    expect(error, findsOneWidget);
    await tester.pump(AppMotion.standard ~/ 2);
    final opening = tester.getSize(regionOf(error)).height;
    await tester.pump(AppMotion.standard);
    await tester.pump();
    final full = tester.getSize(regionOf(error)).height;
    expect(opening, inExclusiveRange(0, full));

    // Trying again clears the error: it folds away still reading the same,
    // rather than going blank.
    pendingAuth = Completer<http.Response>();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump();
    await tester.pump(AppMotion.standard ~/ 2);
    expect(error, findsOneWidget);
    expect(tester.getSize(regionOf(error)).height, inExclusiveRange(0, full));
    final semantics = tester.ensureSemantics();
    expect(find.semantics.byLabel(RegExp("You're offline")), findsNothing);
    semantics.dispose();
    await tester.pump(AppMotion.standard);
    await tester.pump();
    expect(error, findsNothing);
    pendingAuth!.complete(http.Response('{}', 400));
    await tester.pump();
    await tester.pump(AppMotion.standard);
  });

  testWidgets('changes land at once under reduced motion', (tester) async {
    await tester.pumpWidget(loginHost(reduceMotion: true));
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    await tester.pump();
    expect(password, findsNothing);
    expect(
      find.text('Continue with your saved plans and history.'),
      findsNothing,
    );
  });
}
