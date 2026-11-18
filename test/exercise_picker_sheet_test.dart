import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gymapp/data/exercise_library.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/spacing.dart';
import 'package:gymapp/widgets/exercise_picker_sheet.dart';
import 'package:gymapp/widgets/muscle_group_illustration.dart';
import 'package:gymapp/widgets/rolling_figure.dart';

/// Every paragraph on screen that cut its text short.
Iterable<String> _clippedText(WidgetTester tester) => tester.allRenderObjects
    .whereType<RenderParagraph>()
    .where((paragraph) => paragraph.didExceedMaxLines)
    .map((paragraph) => paragraph.text.toPlainText());

class _PickerHarness extends StatefulWidget {
  final List<String> initialNames;

  const _PickerHarness({this.initialNames = const []});

  @override
  State<_PickerHarness> createState() => _PickerHarnessState();
}

class _PickerHarnessState extends State<_PickerHarness> {
  late final List<String> names = List<String>.from(widget.initialNames);

  void _showPicker() {
    showExercisePickerSheet(
      context,
      selectedExerciseNames: names,
      onAdd: (name) => setState(() => names.add(name)),
      onRemove:
          (name) => setState(
            () => names.removeWhere(
              (selected) => selected.toLowerCase() == name.toLowerCase(),
            ),
          ),
      selectionOwner: 'test workout',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: _showPicker,
          child: const Text('Open picker'),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// The tappable card or row of a muscle group.
  Finder groupTile(String group) =>
      find.ancestor(of: find.text(group), matching: find.byType(InkWell));

  double pressScale(WidgetTester tester, String group) =>
      tester
          .widget<AnimatedScale>(
            find.ancestor(
              of: find.text(group),
              matching: find.byType(AnimatedScale),
            ),
          )
          .scale;

  Future<void> pumpPicker(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    double keyboardInset = 0,
    Brightness brightness = Brightness.light,
    List<String> initialNames = const [],
    bool disableAnimations = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF00A2FF), brightness),
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                viewInsets: EdgeInsets.only(bottom: keyboardInset),
                disableAnimations: disableAnimations,
              ),
              child: child!,
            ),
        home: _PickerHarness(initialNames: initialNames),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
  }

  testWidgets('system Back steps out of categories and selected exercises', (
    tester,
  ) async {
    await pumpPicker(tester, initialNames: const ['Bench Press']);
    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Muscle groups'), findsOneWidget);
    expect(find.text('Selected (1)'), findsOneWidget);
    await tester.tap(find.text('Selected (1)'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Muscle groups'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Add exercises'), findsNothing);
  });

  testWidgets('Done still steps back before closing from muscle groups', (
    tester,
  ) async {
    await pumpPicker(tester, initialNames: const ['Bench Press']);
    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Muscle groups'), findsOneWidget);
    await tester.tap(find.text('Selected (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Muscle groups'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Add exercises'), findsNothing);
  });

  testWidgets('adapts to narrow width, large text, and keyboard insets', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      size: const Size(320, 700),
      textScale: 1.5,
      keyboardInset: 240,
    );

    expect(find.text('Add exercises'), findsOneWidget);
    expect(find.text('Selected (0)'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getTopLeft(find.text('Done')).dy, lessThan(700 - 240));
  });

  testWidgets('one-column rows hold selections and large text unclipped', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      size: const Size(320, 700),
      textScale: 1.5,
      initialNames: const ['Bench Press', 'Incline Bench Press'],
    );
    expect(tester.takeException(), isNull);
    expect(_clippedText(tester), isEmpty);

    // One column: each group is a full-width row under the last.
    final chest = tester.getRect(groupTile('Chest'));
    final back = tester.getRect(groupTile('Back'));
    expect(back.left, chest.left);
    expect(back.top, greaterThan(chest.bottom));
    expect(chest.width, back.width);
    final badgeText = find.descendant(
      of: groupTile('Chest'),
      matching: find.text('2'),
    );
    expect(badgeText, findsOneWidget);
    // The badge keeps its own size instead of stretching to the row.
    final badge = find.ancestor(
      of: badgeText,
      matching: find.byType(Container),
    );
    expect(tester.getSize(badge.first).height, lessThan(chest.height / 2));
    expect(find.text('2 of 13 selected'), findsOneWidget);

    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('13 exercises · 2 selected'), findsOneWidget);
    expect(find.byType(MuscleGroupIllustration), findsOneWidget);
  });

  for (final (scale, width) in [(1.0, 390.0), (1.3, 430.0)]) {
    testWidgets(
      'two-column cards keep rows even and fill the sheet at $scale',
      (tester) async {
        await pumpPicker(tester, size: Size(width, 844), textScale: scale);
        expect(tester.takeException(), isNull);
        final chest = tester.getRect(groupTile('Chest'));
        final back = tester.getRect(groupTile('Back'));
        expect(back.top, chest.top);
        expect(back.height, chest.height);
        expect(back.left, greaterThan(chest.right));
        // The three rows reach the bottom of the grid instead of leaving half
        // the sheet empty.
        final grid = tester.getRect(
          find.byKey(const ValueKey('muscle-group-grid')),
        );
        final core = tester.getRect(groupTile('Core'));
        expect(core.bottom, lessThanOrEqualTo(grid.bottom));
        expect(grid.bottom - core.bottom, lessThan(48));
      },
    );
  }

  for (final (width, scale) in [(360.0, 1.3), (390.0, 1.3), (390.0, 2.0)]) {
    testWidgets('nothing clips at $width wide with $scale text', (
      tester,
    ) async {
      // Twelve chest exercises, so the footer says "Selected (12)" and the
      // card's summary is its longest.
      final chest = ExerciseLibrary.exercisesByCategory['Chest']!;
      await pumpPicker(
        tester,
        size: Size(width, 844),
        textScale: scale,
        initialNames: chest.take(12).toList(),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Selected (12)'), findsOneWidget);
      expect(_clippedText(tester), isEmpty);
      // Too little room per letter for two cards side by side.
      final chestRow = tester.getRect(groupTile('Chest'));
      expect(
        tester.getRect(groupTile('Back')).top,
        greaterThan(chestRow.bottom),
      );
    });
  }

  testWidgets('a group with selections shows its count on a badge', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      initialNames: const ['Bench Press', 'Incline Bench Press'],
    );

    final badgeText = find.descendant(
      of: groupTile('Chest'),
      matching: find.text('2'),
    );
    expect(badgeText, findsOneWidget);
    final badge = tester.widget<Container>(
      find.ancestor(of: badgeText, matching: find.byType(Container)).first,
    );
    final context = tester.element(badgeText);
    expect(
      (badge.decoration! as BoxDecoration).color,
      accentFillColor(context),
    );
    expect(tester.widget<Text>(badgeText).style?.color, onAccentColor(context));
    expect(find.text('2 of 13 selected'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Chest, 13 exercises, 2 selected'),
      findsOneWidget,
    );
    // Groups without selections carry no badge.
    expect(
      find.descendant(
        of: groupTile('Back'),
        matching: find.textContaining(RegExp(r'^\d+$')),
      ),
      findsNothing,
    );

    // Deselecting one in the category brings the badge down to match.
    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: groupTile('Chest'), matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.text('1 of 13 selected'), findsOneWidget);
  });

  testWidgets('pages trade places and the leaving page goes once settled', (
    tester,
  ) async {
    await pumpPicker(tester);
    final grid = find.byKey(const ValueKey('muscle-group-grid'));

    await tester.tap(find.text('Chest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Mid-way both pages are mounted; the leaving one takes no taps.
    expect(grid, findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(
      tester
          .widget<IgnorePointer>(
            find.ancestor(of: grid, matching: find.byType(IgnorePointer)).first,
          )
          .ignoring,
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(grid, findsNothing);
    expect(find.text('Muscle groups'), findsNothing);
    expect(find.text('Bench Press'), findsOneWidget);

    // Changing course mid-way settles on the last page asked for. The
    // arriving page takes taps once it can be seen.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.text('Back'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(grid, findsNothing);
    expect(find.text('Barbell Row'), findsOneWidget);
    expect(find.text('Bench Press'), findsNothing);

    // Typing on in a search keeps the results page instead of replaying the
    // transition for every keystroke.
    final search = find.widgetWithText(TextField, 'Search exercises');
    await tester.enterText(search, 'pre');
    await tester.pumpAndSettle();
    await tester.enterText(search, 'pres');
    await tester.pump();
    expect(find.textContaining(RegExp(r'^\d+ results?$')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Barbell Row'), findsNothing);
  });

  testWidgets('returning to a page before it has left shows it once', (
    tester,
  ) async {
    await pumpPicker(tester);
    final grid = find.byKey(const ValueKey('muscle-group-grid'));
    await tester.tap(find.text('Chest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    // The copy still leaving stays hidden from screen readers and taps; only
    // the returning one counts.
    // Searched in the live semantics tree, which is what a screen reader
    // reads; a render object keeps its last node even once excluded.
    expect(find.semantics.byLabel(RegExp('^Chest, 13 exercises')), findsOne);
    // Nor does the leaving copy fade back in alongside it.
    final visible = tester
        .widgetList<Opacity>(
          find.ancestor(of: grid, matching: find.byType(Opacity)),
        )
        .where((opacity) => opacity.opacity > 0);
    expect(visible.length, lessThanOrEqualTo(1));
    await tester.pumpAndSettle();
    expect(grid, findsOneWidget);
    expect(find.text('Bench Press'), findsNothing);
  });

  testWidgets('arriving rows ignore taps until they can be seen', (
    tester,
  ) async {
    await pumpPicker(tester);
    await tester.tap(find.text('Chest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    // A quick second tap where a row is about to appear selects nothing.
    await tester.tap(find.text('Bench Press'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Selected (0)'), findsOneWidget);
  });

  testWidgets(
    'reduced motion changes pages at once and skips the press scale',
    (tester) async {
      await pumpPicker(tester, disableAnimations: true);
      final grid = find.byKey(const ValueKey('muscle-group-grid'));

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Chest')),
      );
      // Inside a scrollable a press registers once the tap deadline passes.
      await tester.pump(kPressTimeout * 2);
      expect(pressScale(tester, 'Chest'), 1);
      await gesture.up();
      await tester.pump();
      expect(grid, findsNothing);
      expect(find.text('Bench Press'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(grid, findsOneWidget);
      expect(find.text('Bench Press'), findsNothing);
    },
  );

  testWidgets('a muscle group gives slightly under the finger', (tester) async {
    await pumpPicker(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Chest')),
    );
    // Inside a scrollable a press registers once the tap deadline passes.
    await tester.pump(kPressTimeout * 2);
    expect(pressScale(tester, 'Chest'), 0.97);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(pressScale(tester, 'Chest'), 1);
  });

  testWidgets('the selected count rolls but reads as one label', (
    tester,
  ) async {
    await pumpPicker(tester);
    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench Press'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Selected (1)'), findsOneWidget);
    expect(find.bySemanticsLabel('Selected (1)'), findsOneWidget);
    // Mid-roll the old number is still on its way out.
    final rolling = find.byType(RollingFigure);
    expect(
      find.descendant(of: rolling, matching: find.text('0')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: rolling, matching: find.text('0')),
      findsNothing,
    );
    expect(find.text('Selected (1)'), findsOneWidget);
    expect(find.text('Selected (0)'), findsNothing);
  });

  testWidgets('selected exercise highlight stays clear of row dividers', (
    tester,
  ) async {
    await pumpPicker(tester, initialNames: const ['Bench Press']);
    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();

    final selectedRow = find.ancestor(
      of: find.text('Bench Press'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color != null,
      ),
    );
    final container = tester.widget<Container>(selectedRow.first);

    expect(
      container.margin,
      const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    );
  });
}
