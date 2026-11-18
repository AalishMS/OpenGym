import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/motion.dart';
import 'package:gymapp/utils/haptics.dart';
import 'package:gymapp/widgets/motion/app_modals.dart';
import 'package:gymapp/widgets/motion/collapsible.dart';
import 'package:gymapp/widgets/motion/entrance.dart';
import 'package:gymapp/widgets/motion/page_switcher.dart';
import 'package:gymapp/widgets/motion/patient_progress.dart';
import 'package:gymapp/widgets/motion/press_scale.dart';
import 'package:gymapp/widgets/motion/state_switcher.dart';
import 'package:gymapp/widgets/motion/surface_fade.dart';
import 'package:gymapp/widgets/plan_title_hero.dart';
import 'package:gymapp/widgets/raised_card.dart';

import 'support/test_fonts.dart';

const Color _seed = Color(0xFF3D7BF7);

/// Built once, so pumping a new host never starts a theme animation.
final ThemeData _theme = buildTheme(_seed, Brightness.light);

/// A bare app around [child], optionally under reduced motion.
Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: _theme,
  home: Builder(
    builder:
        (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(body: child),
        ),
  ),
);

/// Pumps until nothing is scheduled, failing if motion never comes to rest.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(tester.binding.hasScheduledFrame, isFalse);
}

void main() {
  setUpAll(loadTestFonts);

  group('PressScale', () {
    const cardKey = ValueKey('card');

    Widget card({
      VoidCallback? onTap,
      VoidCallback? onLongPress,
      bool enabled = true,
    }) => Center(
      child: PressScale(
        enabled: enabled,
        builder:
            (context, onHighlightChanged) => Material(
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                onHighlightChanged: onHighlightChanged,
                child: const SizedBox(key: cardKey, width: 200, height: 100),
              ),
            ),
      ),
    );

    double width(WidgetTester tester) =>
        tester.getRect(find.byKey(cardKey)).width;

    testWidgets('gives under a held press and returns on release', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(_host(card(onTap: () => taps++)));
      expect(width(tester), 200);

      final press = await tester.startGesture(
        tester.getCenter(find.byKey(cardKey)),
      );
      await tester.pump();
      await tester.pump(AppMotion.quick);
      expect(width(tester), closeTo(200 * AppMotion.scale, 0.01));

      await press.up();
      await _settle(tester);
      expect(width(tester), 200);
      expect(taps, 1, reason: 'the press must not eat the tap');
    });

    testWidgets('leaves long presses, ink and semantics to the object', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var longPresses = 0;
      await tester.pumpWidget(
        _host(card(onTap: () {}, onLongPress: () => longPresses++)),
      );
      await tester.longPress(find.byKey(cardKey));
      await _settle(tester);
      expect(longPresses, 1);
      expect(width(tester), 200);
      expect(
        tester.getSemantics(find.byType(InkWell)),
        isSemantics(hasTapAction: true, hasLongPressAction: true),
      );
      handle.dispose();
    });

    testWidgets('lets a scroll through without staying pressed', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          ListView(
            controller: controller,
            children: [
              const SizedBox(height: 100),
              card(onTap: () {}),
              for (var i = 0; i < 20; i++) const SizedBox(height: 100),
            ],
          ),
        ),
      );
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(cardKey)),
      );
      await drag.moveBy(const Offset(0, -40));
      await tester.pump();
      await drag.moveBy(const Offset(0, -40));
      await tester.pump(AppMotion.quick);
      expect(controller.offset, greaterThan(0));
      expect(width(tester), 200, reason: 'a scroll is not a press');
      await drag.up();
      await _settle(tester);
    });

    testWidgets('stays still when disabled or under reduced motion', (
      tester,
    ) async {
      for (final (enabled, reduceMotion) in [(false, false), (true, true)]) {
        await tester.pumpWidget(
          _host(
            card(onTap: () {}, enabled: enabled),
            reduceMotion: reduceMotion,
          ),
        );
        final press = await tester.startGesture(
          tester.getCenter(find.byKey(cardKey)),
        );
        await tester.pump();
        await tester.pump(AppMotion.quick);
        expect(width(tester), 200);
        await press.up();
        await _settle(tester);
      }
    });

    testWidgets('releases cleanly when the action goes away mid-press', (
      tester,
    ) async {
      VoidCallback? onTap = () {};
      late StateSetter update;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return card(onTap: onTap);
            },
          ),
        ),
      );
      final press = await tester.startGesture(
        tester.getCenter(find.byKey(cardKey)),
      );
      await tester.pump(AppMotion.quick);
      update(() => onTap = null);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(width(tester), 200);
      await press.up();
      await _settle(tester);
    });
  });

  group('RaisedCard', () {
    const contentKey = ValueKey('content');

    Widget raisedCard({bool raised = true, VoidCallback? onTap}) => Center(
      child: RaisedCard(
        raised: raised,
        onTap: onTap,
        child: const SizedBox(key: contentKey, width: 200, height: 100),
      ),
    );

    Future<double> heldWidth(WidgetTester tester) async {
      final press = await tester.startGesture(
        tester.getCenter(find.byKey(contentKey)),
      );
      await tester.pump();
      await tester.pump(AppMotion.quick);
      final width = tester.getRect(find.byKey(contentKey)).width;
      await press.up();
      await _settle(tester);
      return width;
    }

    testWidgets('a tappable raised card gives under the finger', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(_host(raisedCard(onTap: () => taps++)));
      expect(await heldWidth(tester), closeTo(200 * AppMotion.scale, 0.01));
      expect(taps, 1);
    });

    testWidgets('a plain row takes only the ink', (tester) async {
      await tester.pumpWidget(_host(raisedCard(raised: false, onTap: () {})));
      expect(await heldWidth(tester), 200);
    });

    testWidgets('a card without an action has no press at all', (tester) async {
      await tester.pumpWidget(_host(raisedCard()));
      expect(find.byType(PressScale), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('a row rising into a card keeps its state', (tester) async {
      final field = GlobalKey<EditableTextState>();
      final controller = TextEditingController(text: 'kept');
      addTearDown(controller.dispose);
      Widget withField(bool raised) => Center(
        child: RaisedCard(
          raised: raised,
          onTap: () {},
          child: SizedBox(
            width: 200,
            child: EditableText(
              key: field,
              controller: controller,
              focusNode: FocusNode(),
              style: const TextStyle(fontSize: 14),
              cursorColor: const Color(0xFF3D7BF7),
              backgroundCursorColor: const Color(0xFF000000),
            ),
          ),
        ),
      );
      await tester.pumpWidget(_host(withField(false)));
      final before = field.currentState;
      await tester.pumpWidget(_host(withField(true)));
      expect(field.currentState, same(before));
    });
  });

  group('Entrance', () {
    const childKey = ValueKey('arriving');

    double opacityOf(WidgetTester tester, Finder entrance) =>
        tester
            .widget<FadeTransition>(
              find
                  .descendant(
                    of: entrance,
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value;

    testWidgets('the child is there and tappable from the first frame', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.topLeft,
            child: Entrance(
              child: TextButton(
                key: childKey,
                onPressed: () => taps++,
                child: const Text('New'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('New'), findsOneWidget);
      expect(find.semantics.byLabel('New'), findsOneWidget);
      expect(opacityOf(tester, find.byType(Entrance)), 0);
      expect(tester.getTopLeft(find.byKey(childKey)).dy, AppMotion.lift);

      await tester.tap(find.byKey(childKey), warnIfMissed: false);
      expect(taps, 1, reason: 'an arrival never blocks input');

      await tester.pump(AppMotion.enter);
      expect(opacityOf(tester, find.byType(Entrance)), 1);
      expect(tester.getTopLeft(find.byKey(childKey)).dy, 0);
      await _settle(tester);
      handle.dispose();
    });

    testWidgets('plays once: a rebuild never replays it', (tester) async {
      Widget build(int index) =>
          _host(Entrance(index: index, child: const Text('Once')));
      await tester.pumpWidget(build(0));
      await _settle(tester);
      await tester.pumpWidget(build(3));
      expect(opacityOf(tester, find.byType(Entrance)), 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('later indexes start a stagger step apart, capped', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              for (final index in [0, 2, 99])
                Entrance(index: index, child: Text('Item $index')),
            ],
          ),
        ),
      );
      Finder entrance(int index) => find.ancestor(
        of: find.text('Item $index'),
        matching: find.byType(Entrance),
      );
      await tester.pump(
        AppMotion.stagger * 2 - const Duration(milliseconds: 1),
      );
      expect(opacityOf(tester, entrance(0)), greaterThan(0));
      expect(opacityOf(tester, entrance(2)), 0);
      // Capped: index 99 starts with index 6, not 99 steps later.
      await tester.pump(
        AppMotion.stagger * (Entrance.maxStaggered - 2) +
            const Duration(milliseconds: 2),
      );
      expect(opacityOf(tester, entrance(99)), greaterThan(0));
      await _settle(tester);
    });

    testWidgets(
      'appears at once when told not to animate or motion is reduced',
      (tester) async {
        for (final (animate, reduceMotion) in [(false, false), (true, true)]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            _host(
              Align(
                alignment: Alignment.topLeft,
                child: Entrance(
                  animate: animate,
                  child: const SizedBox(key: childKey, width: 10, height: 10),
                ),
              ),
              reduceMotion: reduceMotion,
            ),
          );
          expect(opacityOf(tester, find.byType(Entrance)), 1);
          expect(tester.getTopLeft(find.byKey(childKey)).dy, 0);
        }
      },
    );
  });

  group('Collapsible', () {
    const bodyKey = ValueKey('body');

    Widget region(bool open, {bool reduceMotion = false}) => _host(
      Align(
        alignment: Alignment.topLeft,
        child: Collapsible(
          open: open,
          child: const SizedBox(
            key: bodyKey,
            width: 100,
            height: 100,
            child: Text('Details'),
          ),
        ),
      ),
      reduceMotion: reduceMotion,
    );

    double shownHeight(WidgetTester tester) =>
        tester.getSize(find.byType(Collapsible)).height;

    testWidgets('starts at rest, open or closed', (tester) async {
      await tester.pumpWidget(region(true));
      expect(shownHeight(tester), 100);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(region(false));
      expect(find.byKey(bodyKey), findsNothing);
    });

    testWidgets('grows open, then folds away and leaves the tree', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(region(false));
      await tester.pumpWidget(region(true));
      expect(find.byKey(bodyKey), findsOneWidget);
      await tester.pump(AppMotion.standard ~/ 2);
      expect(shownHeight(tester), inExclusiveRange(0, 100));
      await _settle(tester);
      expect(shownHeight(tester), 100);

      await tester.pumpWidget(region(false));
      await tester.pump(AppMotion.standard ~/ 2);
      expect(find.byKey(bodyKey), findsOneWidget);
      await _settle(tester);
      expect(find.byKey(bodyKey), findsNothing);
      expect(find.semantics.byLabel('Details'), findsNothing);
      expect(shownHeight(tester), 0);
      handle.dispose();
    });

    testWidgets('closing, it takes no taps, focus or semantics at once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var taps = 0;
      Widget form(bool open) => _host(
        Align(
          alignment: Alignment.topLeft,
          child: Collapsible(
            open: open,
            child: TextButton(
              focusNode: focus,
              onPressed: () => taps++,
              child: const Text('Send'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(form(true));
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);

      await tester.pumpWidget(form(false));
      await tester.pump();
      // Still painted on its way out, but already inert.
      expect(find.text('Send'), findsOneWidget);
      expect(focus.hasFocus, isFalse);
      expect(find.semantics.byLabel('Send'), findsNothing);
      await tester.tap(find.text('Send'), warnIfMissed: false);
      expect(taps, 0);

      // Opening again midway, it takes all three back.
      await tester.pumpWidget(form(true));
      await tester.pump();
      expect(find.semantics.byLabel('Send'), findsOneWidget);
      await tester.tap(find.text('Send'));
      expect(taps, 1);
      await _settle(tester);
      handle.dispose();
    });

    testWidgets('started open and told to close, it folds away and reports '
        'it has gone', (tester) async {
      var closed = 0;
      Widget row({bool reduceMotion = false}) => _host(
        Align(
          alignment: Alignment.topLeft,
          child: Collapsible(
            initiallyOpen: true,
            open: false,
            onClosed: () => closed++,
            child: const SizedBox(key: bodyKey, width: 100, height: 100),
          ),
        ),
        reduceMotion: reduceMotion,
      );
      await tester.pumpWidget(row());
      // Holding its place on its first frame, then giving way at once.
      expect(shownHeight(tester), 100);
      await tester.pump(AppMotion.standard ~/ 2);
      expect(shownHeight(tester), inExclusiveRange(0, 50));
      expect(closed, 0);
      await _settle(tester);
      expect(find.byKey(bodyKey), findsNothing);
      expect(closed, 1);

      // Under reduced motion it is gone at once, and still says so, once the
      // frame is done.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(row(reduceMotion: true));
      expect(find.byKey(bodyKey), findsNothing);
      await tester.pump();
      expect(closed, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clips while it folds, and not once it has settled', (
      tester,
    ) async {
      // A settled region must let what it holds paint past its edge, or a
      // raised card's shadow is cut square and reads as a grey band.
      Iterable<Clip> clips() => tester
          .widgetList<ClipRect>(
            find.ancestor(
              of: find.byKey(bodyKey),
              matching: find.descendant(
                of: find.byType(Collapsible),
                matching: find.byType(ClipRect),
              ),
            ),
          )
          .map((clip) => clip.clipBehavior);

      await tester.pumpWidget(region(true));
      expect(clips(), isNotEmpty);
      expect(clips(), everyElement(Clip.none));

      await tester.pumpWidget(region(false));
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 2);
      expect(clips(), contains(Clip.hardEdge));
      await _settle(tester);

      await tester.pumpWidget(region(true));
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 2);
      expect(clips(), contains(Clip.hardEdge));
      await _settle(tester);
      expect(clips(), everyElement(Clip.none));
    });

    testWidgets('opens and closes at once under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(region(false, reduceMotion: true));
      await tester.pumpWidget(region(true, reduceMotion: true));
      await tester.pump();
      expect(shownHeight(tester), 100);
      await tester.pumpWidget(region(false, reduceMotion: true));
      await tester.pump();
      expect(find.byKey(bodyKey), findsNothing);
    });
  });

  group('StateSwitcher', () {
    Widget showing(String state, {bool reduceMotion = false, double? size}) =>
        _host(
          Align(
            alignment: Alignment.topLeft,
            child: StateSwitcher(
              animateSize: size != null,
              child: SizedBox(
                key: ValueKey(state),
                width: size ?? 100,
                height: size ?? 40,
                child: Text(state),
              ),
            ),
          ),
          reduceMotion: reduceMotion,
        );

    testWidgets('crosses to the new state, which is there at once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(showing('Loading'));
      await tester.pumpWidget(showing('Ready'));
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Loading'), findsOneWidget);
      // The leaving state is already out of the semantics tree, and both sit
      // at the same place so nothing jumps.
      expect(find.semantics.byLabel('Loading'), findsNothing);
      expect(find.semantics.byLabel('Ready'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Ready')),
        tester.getTopLeft(find.text('Loading')),
      );
      await _settle(tester);
      expect(find.text('Loading'), findsNothing);
      handle.dispose();
    });

    testWidgets('the leaving state takes no taps', (tester) async {
      var oldTaps = 0;
      Widget button(String label, VoidCallback onPressed) => _host(
        Align(
          alignment: Alignment.topLeft,
          child: StateSwitcher(
            child: TextButton(
              key: ValueKey(label),
              onPressed: onPressed,
              child: Text(label),
            ),
          ),
        ),
      );
      await tester.pumpWidget(button('Save', () => oldTaps++));
      await tester.pumpWidget(button('Saving', () {}));
      await tester.pump();
      await tester.tap(find.text('Save'), warnIfMissed: false);
      expect(oldTaps, 0);
      await _settle(tester);
    });

    testWidgets('the leaving state gives up keyboard focus', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      Widget button(String label) => _host(
        Align(
          alignment: Alignment.topLeft,
          child: StateSwitcher(
            child: TextButton(
              key: ValueKey(label),
              focusNode: label == 'Clear' ? focus : null,
              onPressed: () {},
              child: Text(label),
            ),
          ),
        ),
      );
      await tester.pumpWidget(button('Clear'));
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await tester.pumpWidget(button('Done'));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      await _settle(tester);
    });

    testWidgets('the same state rebuilds in place', (tester) async {
      await tester.pumpWidget(showing('Ready'));
      await tester.pumpWidget(showing('Ready'));
      expect(
        find.descendant(
          of: find.byType(StateSwitcher),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );
    });

    testWidgets('eases to the new size when asked', (tester) async {
      await tester.pumpWidget(showing('Small', size: 40));
      await tester.pumpWidget(showing('Large', size: 120));
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 2);
      expect(
        tester.getSize(find.byType(StateSwitcher)).height,
        inExclusiveRange(40, 120),
      );
      await _settle(tester);
      expect(tester.getSize(find.byType(StateSwitcher)).height, 120);
    });

    testWidgets('changes at once under reduced motion', (tester) async {
      await tester.pumpWidget(showing('Loading', reduceMotion: true));
      await tester.pumpWidget(showing('Ready', reduceMotion: true));
      await tester.pump();
      expect(find.text('Loading'), findsNothing);
      expect(find.text('Ready'), findsOneWidget);
    });

    testWidgets('takes its new size at once under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(showing('Small', reduceMotion: true, size: 40));
      await tester.pumpWidget(showing('Large', reduceMotion: true, size: 120));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(StateSwitcher)).height, 120);
      await tester.pumpWidget(showing('Small', reduceMotion: true, size: 40));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(StateSwitcher)).height, 40);
    });
  });

  group('PageSwitcher', () {
    Widget pages(
      String page, {
      bool forward = true,
      bool reduceMotion = false,
      TextDirection direction = TextDirection.ltr,
      VoidCallback? onTap,
      FocusNode? focus,
    }) => _host(
      Directionality(
        textDirection: direction,
        child: SizedBox(
          width: 300,
          height: 200,
          child: PageSwitcher(
            forward: forward,
            child: Align(
              key: ValueKey(page),
              alignment: Alignment.topLeft,
              child: TextButton(
                key: ValueKey('$page-button'),
                focusNode: focus,
                onPressed: onTap ?? () {},
                child: Text(page),
              ),
            ),
          ),
        ),
      ),
      reduceMotion: reduceMotion,
    );

    double left(WidgetTester tester, String page) =>
        tester.getTopLeft(find.byKey(ValueKey('$page-button'))).dx;

    testWidgets('the arriving page is there, tappable and announced from its '
        'first frame', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(pages('Groups'));
      await tester.pumpWidget(pages('Chest', onTap: () => taps++));
      expect(find.text('Chest'), findsOneWidget);
      expect(find.semantics.byLabel('Chest'), findsOneWidget);
      await tester.tap(find.text('Chest'));
      expect(taps, 1, reason: 'a trade never blocks input');
      await _settle(tester);
      expect(find.text('Groups'), findsNothing);
      handle.dispose();
    });

    testWidgets('the leaving page takes no taps, focus or semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var oldTaps = 0;
      await tester.pumpWidget(
        pages('Groups', focus: focus, onTap: () => oldTaps++),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.pumpWidget(pages('Chest'));
      await tester.pump();
      expect(find.text('Groups'), findsOneWidget);
      expect(focus.hasFocus, isFalse);
      expect(find.semantics.byLabel('Groups'), findsNothing);
      await tester.tap(find.text('Groups'), warnIfMissed: false);
      expect(oldTaps, 0);
      await _settle(tester);
      handle.dispose();
    });

    testWidgets('trades places in the direction of travel and settles', (
      tester,
    ) async {
      await tester.pumpWidget(pages('Groups'));
      final rest = left(tester, 'Groups');

      // Deeper: the new page comes from the end side, the old goes toward
      // the start.
      await tester.pumpWidget(pages('Chest'));
      await tester.pump(AppMotion.standard ~/ 4);
      expect(left(tester, 'Chest'), greaterThan(rest));
      expect(left(tester, 'Chest'), lessThanOrEqualTo(rest + AppMotion.shift));
      expect(left(tester, 'Groups'), lessThan(rest));
      await _settle(tester);
      expect(left(tester, 'Chest'), rest);

      // Back: from the start side.
      await tester.pumpWidget(pages('Groups', forward: false));
      await tester.pump(AppMotion.standard ~/ 4);
      expect(left(tester, 'Groups'), lessThan(rest));
      expect(left(tester, 'Chest'), greaterThan(rest));
      await _settle(tester);
      expect(left(tester, 'Groups'), rest);
    });

    testWidgets('the leaving page clears out before the arriving one is in', (
      tester,
    ) async {
      double opacity(String page) =>
          tester
              .widget<Opacity>(
                find
                    .ancestor(
                      of: find.byKey(ValueKey('$page-button')),
                      matching: find.byType(Opacity),
                    )
                    .first,
              )
              .opacity;
      await tester.pumpWidget(pages('Groups'));
      await tester.pumpWidget(pages('Chest'));
      await tester.pump(AppMotion.standard * 3 ~/ 10);
      expect(opacity('Chest'), 0);
      expect(opacity('Groups'), inExclusiveRange(0, 0.2));
      await tester.pump(AppMotion.standard ~/ 10);
      expect(opacity('Groups'), 0);
      expect(opacity('Chest'), greaterThan(0));
      await _settle(tester);
    });

    testWidgets('mirrors under right-to-left', (tester) async {
      await tester.pumpWidget(pages('Groups', direction: TextDirection.rtl));
      final rest = left(tester, 'Groups');
      await tester.pumpWidget(pages('Chest', direction: TextDirection.rtl));
      await tester.pump(AppMotion.standard ~/ 4);
      // Deeper arrives from the end side, which is the left.
      expect(left(tester, 'Chest'), lessThan(rest));
      expect(left(tester, 'Groups'), greaterThan(rest));
      await _settle(tester);
    });

    testWidgets('the same key rebuilds in place', (tester) async {
      await tester.pumpWidget(pages('Search'));
      await tester.pumpWidget(pages('Search'));
      expect(find.byType(PageSwitchTransition), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('changes at once under reduced motion', (tester) async {
      await tester.pumpWidget(pages('Groups', reduceMotion: true));
      await tester.pumpWidget(pages('Chest', reduceMotion: true));
      await tester.pump();
      expect(find.text('Groups'), findsNothing);
      expect(find.text('Chest'), findsOneWidget);
    });

    testWidgets('pages never share the route\'s primary scroll controller', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        Widget list(String page) => _host(
          PageSwitcher(
            forward: true,
            child: ListView(
              key: ValueKey(page),
              children: [for (var i = 0; i < 40; i++) Text('$page $i')],
            ),
          ),
        );
        await tester.pumpWidget(list('Groups'));
        await tester.pumpWidget(list('Chest'));
        await tester.pump();
        final controllers = [
          for (final element in find.byType(Scrollable).evaluate())
            (element as StatefulElement).state as ScrollableState,
        ].map((scrollable) => scrollable.position);
        expect(controllers.toSet(), hasLength(2));
        final primary = PrimaryScrollController.maybeOf(
          tester.element(find.byType(Scaffold)),
        );
        expect(primary?.hasClients ?? false, isFalse);
        await _settle(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('driven by an animation of its own, a page that has gone is '
        'offstage but alive', (tester) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: AppMotion.standard,
      );
      addTearDown(controller.dispose);
      final field = GlobalKey<EditableTextState>();
      final text = TextEditingController(text: 'kept');
      addTearDown(text.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _host(
          Stack(
            children: [
              PageSwitchTransition(
                animation: ReverseAnimation(controller),
                forward: true,
                child: EditableText(
                  key: field,
                  controller: text,
                  focusNode: focus,
                  style: const TextStyle(fontSize: 14),
                  cursorColor: const Color(0xFF3D7BF7),
                  backgroundCursorColor: const Color(0xFF000000),
                ),
              ),
              PageSwitchTransition(
                animation: controller,
                forward: true,
                child: const Text('Details'),
              ),
            ],
          ),
        ),
      );
      final state = field.currentState;
      expect(find.text('Details'), findsNothing);
      controller.forward();
      await tester.pump();
      expect(find.text('Details'), findsOneWidget);
      await _settle(tester);
      // The catalog is offstage, its state kept for the way back.
      expect(find.byKey(field), findsNothing);
      expect(find.byKey(field, skipOffstage: false), findsOneWidget);
      controller.reverse();
      await _settle(tester);
      expect(field.currentState, same(state));
      expect(find.text('Details'), findsNothing);
    });
  });

  group('SurfaceFade', () {
    const contentKey = ValueKey('content');

    Widget surface(
      Object? identity, {
      bool enabled = true,
      bool reduceMotion = false,
      bool tickers = true,
    }) => _host(
      TickerMode(
        enabled: tickers,
        child: SurfaceFade(
          identity: identity,
          enabled: enabled,
          child: TextButton(
            key: contentKey,
            onPressed: () {},
            child: Text('$identity'),
          ),
        ),
      ),
      reduceMotion: reduceMotion,
    );

    double opacity(WidgetTester tester) =>
        tester
            .widget<FadeTransition>(
              find
                  .ancestor(
                    of: find.byKey(contentKey),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value;

    testWidgets('a new surface starts at the floor, never at nothing', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(surface('Home'));
      expect(opacity(tester), 1);
      await tester.pumpWidget(surface('History'));
      // The first frame already shows what replaced it, and the old one is
      // gone rather than crossing beneath.
      expect(opacity(tester), SurfaceFade.floor);
      expect(find.text('Home'), findsNothing);
      expect(find.semantics.byLabel('History'), findsOneWidget);
      expect(find.byKey(contentKey).hitTestable(), findsOneWidget);
      await tester.pump(AppMotion.quick ~/ 2);
      expect(opacity(tester), inExclusiveRange(SurfaceFade.floor, 1));
      await tester.pump(AppMotion.quick ~/ 2);
      expect(opacity(tester), 1);
      await _settle(tester);
      handle.dispose();
    });

    testWidgets('a rebuild with the same identity replays nothing', (
      tester,
    ) async {
      await tester.pumpWidget(surface('Home'));
      await tester.pumpWidget(surface('Home'));
      expect(opacity(tester), 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('lands at rest when disabled, out of view, under reduced '
        'motion, or on the first load', (tester) async {
      for (final (from, to, enabled, tickers, reduceMotion) in [
        ('Home', 'History', false, true, false),
        ('Home', 'History', true, false, false),
        ('Home', 'History', true, true, true),
        (null, 'Home', true, true, false),
        ('Home', null, true, true, false),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          surface(
            from,
            enabled: enabled,
            tickers: tickers,
            reduceMotion: reduceMotion,
          ),
        );
        await tester.pumpWidget(
          surface(
            to,
            enabled: enabled,
            tickers: tickers,
            reduceMotion: reduceMotion,
          ),
        );
        expect(opacity(tester), 1, reason: '$from to $to');
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
    });
  });

  group('PatientProgress', () {
    const progressKey = ValueKey('progress');

    Widget waiting(
      String? label, {
      bool fold = false,
      bool reduceMotion = false,
    }) => _host(
      Column(
        children: [
          PatientProgress(
            fold: fold,
            child:
                label == null
                    ? null
                    : Semantics(
                      label: label,
                      child: const SizedBox(
                        key: progressKey,
                        width: 100,
                        height: 40,
                        child: ColoredBox(color: Color(0xFF3D7BF7)),
                      ),
                    ),
          ),
          const SizedBox(key: ValueKey('below'), height: 10),
        ],
      ),
      reduceMotion: reduceMotion,
    );

    double opacity(WidgetTester tester) =>
        tester
            .widget<FadeTransition>(
              find
                  .ancestor(
                    of: find.byKey(progressKey),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value;

    double below(WidgetTester tester) =>
        tester.getTopLeft(find.byKey(const ValueKey('below'))).dy;

    testWidgets('work done within patience leaves no trace', (tester) async {
      await tester.pumpWidget(waiting(null));
      await tester.pumpWidget(waiting('Saving'));
      expect(find.byKey(progressKey), findsOneWidget);
      expect(opacity(tester), 0);
      await tester.pump(AppMotion.patience - const Duration(milliseconds: 20));
      expect(opacity(tester), 0);
      await tester.pumpWidget(waiting(null));
      expect(find.byKey(progressKey), findsNothing);
      await tester.pump(AppMotion.patience);
      expect(find.byKey(progressKey), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('in place, it is announced at once and painted after '
        'patience', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(waiting(null));
      await tester.pumpWidget(waiting('Saving'));
      expect(find.semantics.byLabel('Saving'), findsOneWidget);
      // Unpainted, it takes no taps either.
      expect(find.byKey(progressKey).hitTestable(), findsNothing);
      await tester.pump(AppMotion.patience);
      await tester.pump(AppMotion.quick ~/ 2);
      expect(opacity(tester), inExclusiveRange(0, 1));
      await tester.pump(AppMotion.quick ~/ 2);
      expect(opacity(tester), 1);
      expect(find.byKey(progressKey).hitTestable(), findsOneWidget);

      // Done: it fades out on its way, already inert and silent, keeping the
      // last progress it had.
      await tester.pumpWidget(waiting(null));
      await tester.pump(AppMotion.quick ~/ 3);
      expect(find.byKey(progressKey), findsOneWidget);
      expect(opacity(tester), inExclusiveRange(0, 1));
      expect(find.semantics.byLabel('Saving'), findsNothing);
      expect(find.byKey(progressKey).hitTestable(), findsNothing);
      await _settle(tester);
      expect(find.byKey(progressKey), findsNothing);
      handle.dispose();
    });

    testWidgets('folded, it takes no room until it opens, then folds away', (
      tester,
    ) async {
      await tester.pumpWidget(waiting(null, fold: true));
      final rest = below(tester);
      await tester.pumpWidget(waiting('Saving', fold: true));
      expect(find.byKey(progressKey, skipOffstage: false), findsOneWidget);
      expect(below(tester), rest);
      await tester.pump(AppMotion.patience);
      await tester.pump(AppMotion.standard ~/ 2);
      expect(below(tester), inExclusiveRange(rest, rest + 40));
      await tester.pump(AppMotion.standard ~/ 2);
      expect(below(tester), rest + 40);

      await tester.pumpWidget(waiting(null, fold: true));
      await tester.pump(AppMotion.standard ~/ 2);
      expect(below(tester), inExclusiveRange(rest, rest + 40));
      await _settle(tester);
      expect(below(tester), rest);
      expect(find.byKey(progressKey, skipOffstage: false), findsNothing);
    });

    testWidgets('work resumed while it leaves brings it straight back', (
      tester,
    ) async {
      await tester.pumpWidget(waiting(null));
      await tester.pumpWidget(waiting('Saving'));
      await tester.pump(AppMotion.patience);
      await _settle(tester);
      await tester.pumpWidget(waiting(null));
      await tester.pump(AppMotion.quick ~/ 3);
      await tester.pumpWidget(waiting('Saving again'));
      await _settle(tester);
      expect(opacity(tester), 1);
      expect(find.bySemanticsLabel('Saving again'), findsOneWidget);
    });

    testWidgets('under reduced motion it still waits, then simply appears', (
      tester,
    ) async {
      await tester.pumpWidget(waiting(null, reduceMotion: true));
      await tester.pumpWidget(waiting('Saving', reduceMotion: true));
      await tester.pump(AppMotion.patience - const Duration(milliseconds: 1));
      expect(opacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(opacity(tester), 1);
      await tester.pumpWidget(waiting(null, reduceMotion: true));
      await tester.pump();
      expect(find.byKey(progressKey), findsNothing);
    });
  });

  group('showAppDialog', () {
    const dialogKey = ValueKey('dialog');

    Widget opener({
      required void Function(Object? result) onResult,
      bool reduceMotion = false,
    }) => _host(
      Builder(
        builder:
            (context) => TextButton(
              onPressed:
                  () async => onResult(
                    await showAppDialog<String>(
                      context: context,
                      builder:
                          (dialogContext) => Center(
                            child: Material(
                              child: TextButton(
                                key: dialogKey,
                                onPressed:
                                    () => Navigator.pop(dialogContext, 'done'),
                                child: const SizedBox(
                                  width: 200,
                                  height: 100,
                                  child: Text('Dialog'),
                                ),
                              ),
                            ),
                          ),
                    ),
                  ),
              child: const Text('Open'),
            ),
      ),
      reduceMotion: reduceMotion,
    );

    double width(WidgetTester tester) =>
        tester.getRect(find.byKey(dialogKey)).width;

    testWidgets('settles in from slightly smaller, taking taps at once', (
      tester,
    ) async {
      Object? result;
      await tester.pumpWidget(opener(onResult: (value) => result = value));
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(find.text('Dialog'), findsOneWidget);
      final settled = tester.getSize(find.byKey(dialogKey)).width;
      expect(width(tester), closeTo(settled * AppMotion.scale, 0.01));

      await tester.pump(AppMotion.standard ~/ 2);
      expect(
        width(tester),
        inExclusiveRange(settled * AppMotion.scale, settled),
      );
      await tester.pump(AppMotion.standard ~/ 2);
      expect(width(tester), settled);

      final route = ModalRoute.of(tester.element(find.byKey(dialogKey)))!;
      expect((route as TransitionRoute).transitionDuration, AppMotion.standard);
      await tester.pumpWidget(opener(onResult: (value) => result = value));
      await tester.tap(find.byKey(dialogKey));
      await _settle(tester);
      expect(result, 'done');
    });

    testWidgets('a mid-arrival tap reaches the dialog', (tester) async {
      Object? result;
      await tester.pumpWidget(opener(onResult: (value) => result = value));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.tap(find.byKey(dialogKey));
      await _settle(tester);
      expect(result, 'done');
    });

    testWidgets('leaves with a plain fade, at full size', (tester) async {
      await tester.pumpWidget(opener(onResult: (_) {}));
      await tester.tap(find.text('Open'));
      await _settle(tester);
      final settled = width(tester);
      await tester.tap(find.byKey(dialogKey));
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 2);
      expect(find.text('Dialog'), findsOneWidget);
      expect(width(tester), settled);
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.byKey(dialogKey),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      // The exit curve clears most of the dialog in the first half.
      expect(fade.opacity.value, lessThan(0.2));
      await _settle(tester);
      expect(find.text('Dialog'), findsNothing);
    });

    testWidgets('appears and goes at once under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(opener(onResult: (_) {}, reduceMotion: true));
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(width(tester), tester.getSize(find.byKey(dialogKey)).width);
      final route = ModalRoute.of(tester.element(find.byKey(dialogKey)))!;
      expect(route.animation!.isCompleted, isTrue);
      await tester.tap(find.byKey(dialogKey));
      await tester.pump();
      expect(find.text('Dialog'), findsNothing);
    });
  });

  group('showAppSheet', () {
    Widget opener({
      required void Function(Object? result) onResult,
      bool reduceMotion = false,
    }) => _host(
      Builder(
        builder:
            (context) => TextButton(
              onPressed:
                  () async => onResult(
                    await showAppSheet<String>(
                      context: context,
                      showDragHandle: true,
                      builder:
                          (sheetContext) => TextButton(
                            onPressed:
                                () => Navigator.pop(sheetContext, 'picked'),
                            child: const Text('Sheet'),
                          ),
                    ),
                  ),
              child: const Text('Open'),
            ),
      ),
      reduceMotion: reduceMotion,
    );

    TransitionRoute<dynamic> routeOf(WidgetTester tester) =>
        ModalRoute.of(tester.element(find.text('Sheet')))!
            as TransitionRoute<dynamic>;

    testWidgets('rises on the app timing and returns its result', (
      tester,
    ) async {
      Object? result;
      await tester.pumpWidget(opener(onResult: (value) => result = value));
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(find.text('Sheet'), findsOneWidget);
      expect(routeOf(tester).transitionDuration, AppMotion.enter);
      expect(routeOf(tester).reverseTransitionDuration, AppMotion.standard);
      // Its own arguments still apply.
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isTrue,
      );
      await _settle(tester);
      await tester.tap(find.text('Sheet'));
      await _settle(tester);
      expect(result, 'picked');
    });

    testWidgets('appears at once under reduced motion', (tester) async {
      await tester.pumpWidget(opener(onResult: (_) {}, reduceMotion: true));
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(routeOf(tester).transitionDuration, Duration.zero);
      expect(routeOf(tester).animation!.isCompleted, isTrue);
    });
  });

  test('every dialog and sheet in lib/ opens through the app wrappers', () {
    final direct = RegExp(
      r'\b(showDialog|showModalBottomSheet|showGeneralDialog|'
      r'showAdaptiveDialog|showCupertinoDialog|showCupertinoModalPopup)\s*[<(]',
    );
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('motion/app_modals.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (direct.hasMatch(lines[i])) offenders.add('${file.path}:${i + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Use showAppDialog / showAppSheet, so every modal moves alike.',
    );
  });

  group('page transitions', () {
    final routes = <String, WidgetBuilder>{
      '/':
          (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.pushNamed(context, '/next'),
              child: const Text('Push'),
            ),
          ),
      '/next': (context) => const Scaffold(body: Text('Next page')),
    };

    Widget app({
      TargetPlatform? platform,
      Brightness brightness = Brightness.light,
    }) => MaterialApp(
      theme: buildTheme(_seed, brightness).copyWith(platform: platform),
      routes: routes,
    );

    Future<void> backGesture(String method, [Object? arguments]) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'flutter/backgesture',
              const StandardMethodCodec().encodeMethodCall(
                MethodCall(method, arguments),
              ),
              (_) {},
            );

    testWidgets('Android: a back swipe previews the page underneath', (
      tester,
    ) async {
      await tester.pumpWidget(app(platform: TargetPlatform.android));
      await tester.tap(find.text('Push'));
      await _settle(tester);
      expect(find.text('Push'), findsNothing);

      await backGesture('startBackGesture', {
        'touchOffset': [5.0, 300.0],
        'progress': 0.0,
        'swipeEdge': 0,
      });
      await tester.pump();
      await backGesture('updateBackGestureProgress', {
        'x': 100.0,
        'y': 300.0,
        'progress': 0.35,
        'swipeEdge': 0,
      });
      await tester.pumpAndSettle();
      expect(find.text('Push'), findsOneWidget, reason: 'previewed underneath');
      expect(find.text('Next page'), findsOneWidget);

      await backGesture('commitBackGesture');
      await _settle(tester);
      expect(find.text('Next page'), findsNothing);
    });

    testWidgets('Android: a page guarding its work still intercepts Back', (
      tester,
    ) async {
      final attempts = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(_seed, Brightness.light),
          home: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder:
                              (_) => PopScope(
                                canPop: false,
                                onPopInvokedWithResult:
                                    (didPop, _) => attempts.add(didPop),
                                child: const Scaffold(body: Text('Unsaved')),
                              ),
                        ),
                      ),
                  child: const Text('Edit'),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await _settle(tester);
      await backGesture('startBackGesture', {
        'touchOffset': [5.0, 300.0],
        'progress': 0.0,
        'swipeEdge': 0,
      });
      await tester.pump();
      await backGesture('commitBackGesture');
      await _settle(tester);
      expect(find.text('Unsaved'), findsOneWidget);
      expect(attempts, [false]);
    });

    testWidgets('iOS: an edge swipe still goes back', (tester) async {
      await tester.pumpWidget(app(platform: TargetPlatform.iOS));
      await tester.tap(find.text('Push'));
      await _settle(tester);
      await tester.dragFrom(const Offset(5, 300), const Offset(500, 0));
      await _settle(tester);
      expect(find.text('Next page'), findsNothing);
      expect(find.text('Push'), findsOneWidget);
    });

    testWidgets('the gap between pages is the page colour, not a raised grey', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(platform: TargetPlatform.android, brightness: Brightness.dark),
      );
      final context = tester.element(find.text('Push'));
      final page = backgroundColor(context);
      final raised = surfaceColor(context);
      await tester.tap(find.text('Push'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final backdrops = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .map((box) => box.color);
      expect(backdrops, contains(page));
      expect(backdrops, isNot(contains(raised)));
      await _settle(tester);
    });

    testWidgets('a push lands at once under reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(app(platform: TargetPlatform.android));
      await tester.tap(find.text('Push'));
      await tester.pump();
      final route = ModalRoute.of(tester.element(find.text('Next page')))!;
      expect(route.animation!.isCompleted, isTrue);
      expect(find.text('Push'), findsNothing);
    });

    testWidgets('the plan name still flies into the workout header', (
      tester,
    ) async {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: _theme.copyWith(platform: platform),
            home: Builder(
              builder:
                  (context) => Scaffold(
                    body: GestureDetector(
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder:
                                  (_) => const Scaffold(
                                    body: Align(
                                      alignment: Alignment.topLeft,
                                      child: PlanTitleHero(
                                        tag: 'plan',
                                        text: 'Push Day',
                                        style: TextStyle(fontSize: 18),
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                      child: const Center(
                        child: PlanTitleHero(
                          tag: 'plan',
                          text: 'Push Day',
                          style: TextStyle(fontSize: 22),
                        ),
                      ),
                    ),
                  ),
            ),
          ),
        );
        await tester.tap(find.text('Push Day'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        final inFlight = tester
            .widgetList<Text>(find.text('Push Day'))
            .map((text) => text.style?.fontSize);
        expect(
          inFlight.any((size) => size != null && size > 18 && size < 22),
          isTrue,
          reason: '$platform',
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('each platform keeps its own transition', (tester) async {
      final builders =
          buildTheme(_seed, Brightness.light).pageTransitionsTheme.builders;
      expect(
        builders[TargetPlatform.android]!.transitionDuration,
        const Duration(
          milliseconds:
              FadeForwardsPageTransitionsBuilder.kTransitionMilliseconds,
        ),
      );
      for (final platform in TargetPlatform.values) {
        expect(builders[platform], isNotNull, reason: '$platform');
      }
    });
  });

  test('the settle spring comes to rest without overshoot', () {
    // A released plan swipe: 28px out, let go at rest.
    final spring = SpringSimulation(AppMotion.settle, 28, 0, 0);
    final standard = AppMotion.standard.inMicroseconds / 1e6;
    for (var t = 0.0; t <= 1; t += 0.005) {
      expect(spring.x(t), greaterThanOrEqualTo(-1e-6), reason: 'at $t s');
    }
    expect(spring.x(standard), lessThan(1));
  });

  testWidgets('a selection tick is the platform selection click', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    Haptics.selection();
    expect(
      calls.map((call) => call.arguments),
      contains('HapticFeedbackType.selectionClick'),
    );
  });
}
