import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/services/update_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/motion.dart';
import 'package:gymapp/widgets/floating_notice.dart';
import 'package:gymapp/widgets/motion/collapsible.dart';
import 'package:gymapp/widgets/update_dialog.dart';

Finder _ignoring(Finder finder) => find.ancestor(
  of: finder,
  matching: find.byWidgetPredicate(
    (widget) => widget is IgnorePointer && widget.ignoring,
  ),
);

void main() {
  group('update dialog', () {
    final release = ReleaseInfo(
      tagName: 'v1.0.0+2',
      displayVersion: 'OpenGym v1.0.0',
      changelog: '- Faster workout startup\n- Fixed the set editor\n',
      htmlUrl: 'https://github.com/AalishMS/OpenGym/releases/tag/v1.0.0%2B2',
      apkUrl: 'https://example.invalid/app.apk',
      apkSize: 1024,
      version: AppVersion.tryParse('1.0.0+2')!,
    );

    Future<_Updates> open(
      WidgetTester tester, {
      bool reduceMotion = false,
    }) async {
      final updates = _Updates(release);
      // Tall enough that the dialog is sized by its content, not the screen.
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // The dialog is pushed above `home`, so reduced motion has to come from
      // the platform, as it does on a device.
      if (reduceMotion) {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
      }
      await tester.pumpWidget(
        ChangeNotifierProvider<UpdateProvider>.value(
          value: updates,
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF7C5CFF), Brightness.dark),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 1000),
                disableAnimations: reduceMotion,
              ),
              child: Scaffold(
                body: Builder(
                  builder:
                      (context) => TextButton(
                        onPressed: () => showUpdateDialog(context),
                        child: const Text('Open'),
                      ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return updates;
    }

    testWidgets('downloading opens its progress as a region and crosses the '
        'buttons', (tester) async {
      final updates = await open(tester);
      // The dialog's own surface, not the full-screen box that centres it.
      final dialog =
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(Material),
              )
              .first;
      final before = tester.getSize(dialog).height;

      await tester.tap(find.text('Update now'));
      await tester.pump();
      // Progress and the new buttons are there at once; the offer that was
      // pressed takes no second tap while it leaves.
      expect(find.text('Downloading update'), findsOneWidget);
      expect(find.text('Cancel download'), findsOneWidget);
      expect(_ignoring(find.text('Update now')), findsWidgets);
      expect(_ignoring(find.text('Cancel download')), findsNothing);
      await tester.pump(AppMotion.standard ~/ 2);
      final growing = tester.getSize(dialog).height;
      await tester.pumpAndSettle();
      final after = tester.getSize(dialog).height;
      expect(after, greaterThan(before));
      expect(growing, inExclusiveRange(before, after));
      expect(find.text('Update now'), findsNothing);

      // Cancelling folds the progress away again.
      await tester.tap(find.text('Cancel download'));
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 2);
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('Downloading update'),
                    matching: find.byType(Collapsible),
                  )
                  .first,
            )
            .height,
        greaterThan(0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Downloading update'), findsNothing);
      expect(tester.getSize(dialog).height, closeTo(before, 0.5));
      expect(updates.cancelCount, 1);
    });

    testWidgets('a failure crosses the notes to the message', (tester) async {
      final updates = await open(tester);
      updates
        ..status = UpdateStatus.failed
        ..notify();
      await tester.pump();
      expect(find.text('Update needs attention'), findsOneWidget);
      expect(find.text('A new build is ready'), findsOneWidget);
      expect(_ignoring(find.text('A new build is ready')), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text('A new build is ready'), findsNothing);
      expect(find.text('Faster workout startup'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('phases change at once under reduced motion', (tester) async {
      await open(tester, reduceMotion: true);
      await tester.tap(find.text('Update now'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Update now'), findsNothing);
      expect(find.text('Downloading update'), findsOneWidget);
    });
  });

  group('floating notice', () {
    Widget host(Widget? notice) => MaterialApp(
      theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
      home: Scaffold(body: FloatingNoticeHost(notice: notice)),
    );

    FloatingNotice notice(String title, VoidCallback onDismiss) =>
        FloatingNotice(
          key: ValueKey(title),
          icon: LucideIcons.cloudOff,
          title: title,
          onDismiss: onDismiss,
        );

    testWidgets('a replaced notice takes no taps while it leaves', (
      tester,
    ) async {
      var firstClosed = 0;
      await tester.pumpWidget(host(notice('First', () => firstClosed++)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(notice('Second', () {})));
      await tester.pump();
      expect(find.text('First'), findsOneWidget);
      expect(_ignoring(find.text('First')), findsWidgets);
      expect(_ignoring(find.text('Second')), findsNothing);
      // The arriving notice is announced once it starts to show.
      await tester.pump(AppMotion.quick ~/ 2);
      final semantics = tester.ensureSemantics();
      expect(find.semantics.byLabel(RegExp('First')), findsNothing);
      expect(find.semantics.byLabel(RegExp('Second')), findsOne);
      semantics.dispose();
      await tester.pumpAndSettle();
      expect(find.text('First'), findsNothing);
      expect(firstClosed, 0);
    });

    testWidgets('arrives on the sheet timing and leaves faster', (
      tester,
    ) async {
      double shown(String title) => tester
          .widgetList<FadeTransition>(
            find.ancestor(
              of: find.text(title),
              matching: find.byType(FadeTransition),
            ),
          )
          .fold(1.0, (opacity, fade) => opacity * fade.opacity.value);

      await tester.pumpWidget(host(null));
      await tester.pumpWidget(host(notice('Hello', () {})));
      // Still arriving past the standard time; in by the enter time.
      await tester.pump(AppMotion.standard);
      expect(shown('Hello'), inExclusiveRange(0, 1));
      await tester.pump(AppMotion.enter - AppMotion.standard);
      expect(shown('Hello'), 1);

      // Leaving takes only the standard time.
      await tester.pumpWidget(host(null));
      await tester.pump(AppMotion.standard - const Duration(milliseconds: 20));
      expect(find.text('Hello'), findsOneWidget);
      expect(shown('Hello'), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 21));
      expect(find.text('Hello'), findsNothing);
    });
  });
}

class _Updates extends UpdateProvider {
  _Updates(this.release);

  @override
  UpdateStatus status = UpdateStatus.available;
  @override
  final ReleaseInfo release;
  var cancelCount = 0;

  @override
  double get progress => 0.42;

  void notify() => notifyListeners();

  @override
  Future<void> startUpdate() async {
    status = UpdateStatus.downloading;
    notifyListeners();
  }

  @override
  Future<void> cancelUpdate() async {
    cancelCount++;
    status = UpdateStatus.available;
    notifyListeners();
  }
}
