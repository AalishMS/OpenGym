import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/screens/settings_screen.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/action_progress.dart';

import 'support/test_fonts.dart';

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final brightness in Brightness.values) {
    testWidgets('accent saves keep settings still in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = _DelayedSettings();
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
                  theme: buildTheme(settings.accentSeed, brightness),
                  home: const SettingsScreen(),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();

      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      final offset = scroll.position.pixels;
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final swatches = [
        for (var i = 0; i < SettingsProvider.accents.length; i++)
          find.byKey(ValueKey('accent-swatch-$i')),
      ];
      final rects = [for (final swatch in swatches) tester.getRect(swatch)];

      void expectSteady() {
        expect(scroll.position.pixels, offset);
        expect(tester.getRect(find.byType(SingleChildScrollView)), viewport);
        for (var i = 0; i < swatches.length; i++) {
          expect(tester.getRect(swatches[i]), rects[i]);
        }
        expect(tester.takeException(), isNull);
      }

      for (var i = 0; i < swatches.length; i++) {
        await tester.tap(swatches[i]);
        await tester.pump();
        expect(find.byType(ActionProgress), findsOneWidget);
        expectSteady();
        await tester.pump(const Duration(milliseconds: 100));
        expectSteady();
        settings.pending.complete();
        await tester.pumpAndSettle();
        expect(settings.accentIndex, i);
        expect(find.byType(ActionProgress), findsNothing);
        expectSteady();
      }

      await tester.tap(swatches.first);
      await tester.pump();
      expectSteady();
      settings.pending.completeError(StateError('storage unavailable'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not complete this action. Try again.'),
        findsOneWidget,
      );
      expect(find.byType(ActionProgress), findsNothing);
      expectSteady();
    });
  }
}

class _DelayedSettings extends SettingsProvider {
  late Completer<void> pending;

  @override
  Future<void> setAccentColor(int index) async {
    pending = Completer<void>();
    await pending.future;
    await super.setAccentColor(index);
  }
}

class _Updates extends UpdateProvider {
  @override
  Future<void> loadInstalledVersion() async {}
}
