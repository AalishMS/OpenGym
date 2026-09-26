import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gymapp/main.dart' show loadIntroPending;
import 'package:gymapp/screens/intro_screen.dart';
import 'package:gymapp/theme/app_theme.dart';

void main() {
  test('new installs keep the intro pending until completion', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await loadIntroPending(), isTrue);
    // A later migration must not make an unfinished intro disappear.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('idkey_migration_v1_done', true);
    expect(await loadIntroPending(), isTrue);
    await prefs.setBool('intro_pending_v1', false);
    expect(await loadIntroPending(), isFalse);
  });

  test('existing installs bypass the intro', () async {
    SharedPreferences.setMockInitialValues({'idkey_migration_v1_done': true});
    expect(await loadIntroPending(), isFalse);
  });

  Widget host(Future<void> Function() onFinish) {
    return MaterialApp(
      theme: buildTheme(const Color(0xFF00CED1), Brightness.light),
      home: IntroScreen(onFinish: onFinish),
    );
  }

  testWidgets('introduces planning, logging, and progress in order', (
    tester,
  ) async {
    var finishes = 0;
    await tester.pumpWidget(host(() async => finishes++));

    expect(find.text('Make a plan that fits you'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Log as you lift'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text("See how far you've come"), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pump();
    expect(finishes, 1);
  });

  testWidgets('Skip finishes immediately and compact screens do not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var finishes = 0;
    await tester.pumpWidget(host(() async => finishes++));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(finishes, 1);
  });
}
