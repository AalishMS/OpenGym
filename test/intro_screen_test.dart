import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gymapp/main.dart' show loadIntroPending;
import 'package:gymapp/screens/intro_screen.dart';
import 'package:gymapp/services/tutorial_preferences.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/motion.dart';

void main() {
  test('new installs keep the intro pending until completion', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await loadIntroPending(), isTrue);
    expect(await TutorialPreferences.isTourPending(), isTrue);
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
    expect(await TutorialPreferences.isTourPending(), isFalse);
  });

  test(
    'finishing the intro leaves the tour pending until it is shown',
    () async {
      SharedPreferences.setMockInitialValues({});
      await loadIntroPending();
      await TutorialPreferences.finishIntro();
      expect(await loadIntroPending(), isFalse);
      expect(await TutorialPreferences.isTourPending(), isTrue);
      await TutorialPreferences.markTourSeen();
      expect(await TutorialPreferences.isTourPending(), isFalse);
      expect(await loadIntroPending(), isFalse);
    },
  );

  test(
    'skipping the intro skips the whole tutorial on future launches',
    () async {
      SharedPreferences.setMockInitialValues({});
      await loadIntroPending();
      await TutorialPreferences.finishIntro(skipTutorial: true);
      expect(await loadIntroPending(), isFalse);
      expect(await TutorialPreferences.isTourPending(), isFalse);
    },
  );

  test(
    'users who already finished the old intro are not prompted again',
    () async {
      SharedPreferences.setMockInitialValues({'intro_pending_v1': false});
      expect(await loadIntroPending(), isFalse);
      expect(await TutorialPreferences.isTourPending(), isFalse);
    },
  );

  Widget host(Future<void> Function() onFinish, {bool reduceMotion = false}) {
    return MaterialApp(
      theme: buildTheme(const Color(0xFF00CED1), Brightness.light),
      home: Builder(
        builder:
            (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reduceMotion),
              child: IntroScreen(onFinish: onFinish),
            ),
      ),
    );
  }

  testWidgets('the page turn leaves from rest and comes to rest', (
    tester,
  ) async {
    await tester.pumpWidget(host(() async {}));
    final page = tester.widget<PageView>(find.byType(PageView));
    final width = tester.getSize(find.byType(PageView)).width;
    await tester.tap(find.text('Next'));
    await tester.pump();
    // An eighth of the way through, a page already on screen has barely
    // started to travel: it eases out of rest rather than lurching off.
    await tester.pump(AppMotion.long ~/ 8);
    final early = page.controller!.offset;
    expect(early, greaterThan(0));
    expect(early, lessThan(width * 0.05));
    await tester.pump(AppMotion.long * 3 ~/ 8);
    expect(page.controller!.offset, closeTo(width / 2, width * 0.05));
    await tester.pumpAndSettle();
    expect(page.controller!.offset, closeTo(width, 0.5));
  });

  testWidgets('under reduced motion Next turns the page at once', (
    tester,
  ) async {
    await tester.pumpWidget(host(() async {}, reduceMotion: true));
    final page = tester.widget<PageView>(find.byType(PageView));
    final width = tester.getSize(find.byType(PageView)).width;
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(page.controller!.offset, width);
    expect(find.text('Log as you lift'), findsOneWidget);
  });

  testWidgets('introduces planning and logging in two slides', (tester) async {
    var finishes = 0;
    await tester.pumpWidget(host(() async => finishes++));

    expect(find.text('Make a plan that fits you'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Log as you lift'), findsOneWidget);

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

  testWidgets('Skip and Back use the skip callback', (tester) async {
    var skips = 0;
    var finishes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF00CED1), Brightness.light),
        home: IntroScreen(
          onFinish: () async => finishes++,
          onSkip: () async => skips++,
        ),
      ),
    );
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(skips, 1);
    expect(finishes, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF00CED1), Brightness.light),
        home: IntroScreen(
          onFinish: () async => finishes++,
          onSkip: () async => skips++,
        ),
      ),
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(skips, 2);
    expect(finishes, 0);
  });
}
