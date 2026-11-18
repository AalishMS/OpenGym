import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/screens/settings_screen.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/motion.dart';
import 'package:gymapp/widgets/action_progress.dart';

import 'support/test_fonts.dart';

const String _coachOff =
    'An AI assistant that builds and edits your plans in a chat. Turn it on '
    'to add a Coach button to the top of Home.';
const String _coachOn = 'Ask the AI Coach to build or change your plans';

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_HeldSettings> pumpSettings(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (reduceMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }
    final settings = _HeldSettings();
    final updates = _Updates();
    addTearDown(settings.dispose);
    addTearDown(updates.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<UpdateProvider>.value(value: updates),
        ],
        child: Consumer<SettingsProvider>(
          builder:
              (context, settings, _) => MaterialApp(
                theme: buildTheme(settings.accentSeed, Brightness.light),
                home: const SettingsScreen(),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  /// The fade a [StateSwitcher] gives [finder]'s state: the nearest one.
  double crossOpacity(WidgetTester tester, Finder finder) =>
      tester
          .widget<FadeTransition>(
            find
                .ancestor(of: finder, matching: find.byType(FadeTransition))
                .first,
          )
          .opacity
          .value;

  /// Lets a save finish, one zero-time frame at a time, until [done].
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 20 && !done(); i++) {
      await tester.pump();
    }
    expect(done(), isTrue);
  }

  bool takesTaps(WidgetTester tester, Finder finder) =>
      !tester
          .widgetList<IgnorePointer>(
            find.ancestor(of: finder, matching: find.byType(IgnorePointer)),
          )
          .any((ignore) => ignore.ignoring);

  group('the saving banner', () {
    testWidgets('fades in over the page and out again', (tester) async {
      final settings = await pumpSettings(tester);
      final banner = find.byType(ActionProgress);
      final swatch = find.byKey(const ValueKey('accent-swatch-1'));
      final before = tester.getRect(swatch);

      await tester.tap(swatch);
      await tester.pump();
      // In the tree and announced from the first frame, on its way in.
      expect(banner, findsOneWidget);
      expect(crossOpacity(tester, banner), lessThan(1));
      await tester.pump(AppMotion.quick);
      expect(crossOpacity(tester, banner), 1);
      expect(tester.getRect(swatch), before);

      settings.accent.complete();
      await settle(tester, () => !takesTaps(tester, banner));
      await tester.pump(AppMotion.quick ~/ 3);
      // Leaving: still fading, already past taking taps or being read.
      expect(banner, findsOneWidget);
      expect(crossOpacity(tester, banner), lessThan(1));
      expect(takesTaps(tester, banner), isFalse);
      await tester.pumpAndSettle();
      expect(banner, findsNothing);
      expect(tester.getRect(swatch), before);
      expect(settings.accentIndex, 1);
    });

    testWidgets('appears and leaves at once under reduced motion', (
      tester,
    ) async {
      final settings = await pumpSettings(tester, reduceMotion: true);
      final banner = find.byType(ActionProgress);
      await tester.tap(find.byKey(const ValueKey('accent-swatch-2')));
      await tester.pump();
      expect(crossOpacity(tester, banner), 1);
      settings.accent.complete();
      await settle(tester, () => banner.evaluate().isEmpty);
      expect(banner, findsNothing);
    });
  });

  group('a switch whose description changes', () {
    testWidgets('crosses to the new line and eases the row height', (
      tester,
    ) async {
      final settings = await pumpSettings(tester);
      final heading = find.text('Data');
      final before = tester.getTopLeft(heading).dy;
      expect(find.text(_coachOff), findsOneWidget);

      await tester.tap(find.text('Coach'));
      await tester.pump();
      settings.coach.complete();
      await settle(tester, () => find.text(_coachOn).evaluate().isNotEmpty);
      // Both lines while they cross; the old one no longer takes taps.
      expect(find.text(_coachOn), findsOneWidget);
      expect(find.text(_coachOff), findsOneWidget);
      expect(takesTaps(tester, find.text(_coachOff)), isFalse);
      expect(crossOpacity(tester, find.text(_coachOn)), lessThan(1));

      // The longer line holds the space while the two cross; once it has
      // gone, the row closes up gradually rather than in one jump.
      for (
        var i = 0;
        i < 10 && find.text(_coachOff).evaluate().isNotEmpty;
        i++
      ) {
        expect(tester.getTopLeft(heading).dy, before);
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text(_coachOff), findsNothing);
      await tester.pump(AppMotion.standard ~/ 2);
      final midway = tester.getTopLeft(heading).dy;
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(heading).dy;
      expect(after, lessThan(before));
      expect(midway, lessThan(before));
      expect(midway, greaterThan(after));
      expect(find.text(_coachOff), findsNothing);
    });

    testWidgets('changes at once under reduced motion', (tester) async {
      final settings = await pumpSettings(tester, reduceMotion: true);
      await tester.tap(find.text('Coach'));
      await tester.pump();
      settings.coach.complete();
      await settle(tester, () => find.text(_coachOn).evaluate().isNotEmpty);
      expect(find.text(_coachOn), findsOneWidget);
      expect(find.text(_coachOff), findsNothing);
    });
  });

  group('the accent swatches', () {
    Finder check(int index) => find.descendant(
      of: find.byKey(ValueKey('accent-swatch-$index')),
      matching: find.byIcon(LucideIcons.check),
    );

    Duration ringDuration(WidgetTester tester, int index) =>
        tester
            .widget<AnimatedContainer>(
              find.descendant(
                of: find.byKey(ValueKey('accent-swatch-$index')),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .duration;

    testWidgets('the check settles with the ring on the quick token', (
      tester,
    ) async {
      final settings = await pumpSettings(tester);
      final from = settings.accentIndex;
      final to = (from + 3) % SettingsProvider.accents.length;
      expect(check(from), findsOneWidget);
      expect(ringDuration(tester, from), AppMotion.quick);

      await tester.tap(find.byKey(ValueKey('accent-swatch-$to')));
      await tester.pump();
      settings.accent.complete();
      await settle(tester, () => check(to).evaluate().isNotEmpty);
      // The new check fades in as the old one fades out.
      expect(check(to), findsOneWidget);
      expect(check(from), findsOneWidget);
      await tester.pump(AppMotion.quick ~/ 3);
      expect(crossOpacity(tester, check(to)), lessThan(1));
      expect(crossOpacity(tester, check(to)), greaterThan(0));
      await tester.pumpAndSettle();
      expect(check(from), findsNothing);
      expect(crossOpacity(tester, check(to)), 1);
    });

    testWidgets('move at once under reduced motion', (tester) async {
      final settings = await pumpSettings(tester, reduceMotion: true);
      final from = settings.accentIndex;
      final to = (from + 3) % SettingsProvider.accents.length;
      expect(ringDuration(tester, from), Duration.zero);
      await tester.tap(find.byKey(ValueKey('accent-swatch-$to')));
      await tester.pump();
      settings.accent.complete();
      await settle(tester, () => check(to).evaluate().isNotEmpty);
      expect(check(to), findsOneWidget);
      expect(check(from), findsNothing);
    });
  });
}

/// Holds each save until the test lets it through.
class _HeldSettings extends SettingsProvider {
  Completer<void> accent = Completer<void>();
  Completer<void> coach = Completer<void>();

  @override
  Future<void> setAccentColor(int index) async {
    await accent.future;
    accent = Completer<void>();
    await super.setAccentColor(index);
  }

  @override
  Future<void> setCoachEnabled(bool value) async {
    await coach.future;
    coach = Completer<void>();
    await super.setCoachEnabled(value);
  }
}

class _Updates extends UpdateProvider {
  @override
  Future<void> loadInstalledVersion() async {}
}
