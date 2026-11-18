import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/motion.dart';
import 'package:gymapp/widgets/workout/set_entry_table.dart';

import 'support/test_fonts.dart';

/// Motion in the shared set table: a set deleted from the hold menu folds
/// away so the rows under it rise into its place, and the record mark pops
/// only when it is earned with the table on screen.
void main() {
  setUpAll(loadTestFonts);

  const sentinel = ValueKey('below-table');

  /// A continuous log, as the workout and the plan editor host it: deletes go
  /// through the hold menu, and the host reserves the keypad's space.
  Widget host(
    ValueNotifier<List<SetEntry>> sets, {
    bool reduceMotion = false,
    void Function(int index)? onDeleted,
  }) => MaterialApp(
    theme: buildTheme(const Color(0xFF008D8D), Brightness.light),
    builder:
        (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder<List<SetEntry>>(
          valueListenable: sets,
          builder:
              (context, entries, _) => Column(
                children: [
                  SetEntryTable(
                    continuousLog: true,
                    sets: entries,
                    onChanged: (_, _, _) {},
                    onDelete: (index) {
                      onDeleted?.call(index);
                      sets.value = [...entries]..removeAt(index);
                    },
                  ),
                  const SizedBox(key: sentinel, height: 48),
                  ValueListenableBuilder<double>(
                    valueListenable: SetEntryTable.keyboardHeight,
                    builder: (_, height, _) => SizedBox(height: height),
                  ),
                ],
              ),
        ),
      ),
    ),
  );

  List<SetEntry> plain(int count) => [
    for (var i = 0; i < count; i++) SetEntry(weight: 60.0 + i, reps: 8),
  ];

  double top(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder).dy;

  Future<void> deleteFromMenu(WidgetTester tester, int index) async {
    await tester.longPress(find.byKey(ValueKey('set_entry_row_$index')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete set'));
  }

  group('deleting a set', () {
    testWidgets('folds the row away so the rows below rise into its place', (
      tester,
    ) async {
      final sets = ValueNotifier(plain(3));
      await tester.pumpWidget(host(sets));
      await tester.pumpAndSettle();
      final before = top(tester, find.byKey(sentinel));
      final rowStep =
          top(tester, find.byKey(const ValueKey('set_entry_row_2'))) -
          top(tester, find.byKey(const ValueKey('set_entry_row_1')));

      await deleteFromMenu(tester, 1);
      await tester.pump();
      expect(sets.value, hasLength(2));
      // The deleted row still holds its place on the first frame...
      expect(top(tester, find.byKey(sentinel)), closeTo(before, 0.5));
      await tester.pump(AppMotion.standard ~/ 2);
      final midway = top(tester, find.byKey(sentinel));
      // ...gives way at once, so it is mostly gone halfway through...
      expect(midway, lessThan(before - rowStep / 2));
      expect(midway, greaterThan(before - rowStep));
      await tester.pumpAndSettle();
      // ...and the rows below end exactly one row higher.
      expect(top(tester, find.byKey(sentinel)), closeTo(before - rowStep, 0.5));
      expect(find.text('3'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the folding row takes no taps and says nothing', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final sets = ValueNotifier(plain(3));
      await tester.pumpWidget(host(sets));
      await tester.pumpAndSettle();
      await deleteFromMenu(tester, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // The old Set 2 is still folding; only the row that took its number
      // is announced.
      expect(find.bySemanticsLabel('Set 2 Kg'), findsOneWidget);
      expect(find.bySemanticsLabel('Set 3 Kg'), findsNothing);
      // A tap on the row rising into place lands there mid-fold.
      await tester.tap(find.bySemanticsLabel('Set 2 Kg'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Set 2 Kg')),
        containsSemantics(isSelected: true),
      );
      expect(find.textContaining('Set 2  ·', findRichText: true), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the keypad still keeps the row it opens on in view', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);
      final sets = ValueNotifier(plain(14));
      await tester.pumpWidget(host(sets));
      await tester.pumpAndSettle();
      await deleteFromMenu(tester, 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // The lowest row wholly on screen, opened while the rows are rising.
      final low = [
        for (var i = 0; i < sets.value.length; i++) i,
      ].lastWhere((i) {
        final row = find.byKey(ValueKey('set_entry_row_$i'));
        return tester.any(row) && tester.getRect(row).bottom < 780;
      });
      await tester.tap(find.bySemanticsLabel('Set ${low + 1} Kg'));
      await tester.pumpAndSettle();
      final keypad = tester.getRect(find.byType(BottomSheet));
      final row = tester.getRect(find.byKey(ValueKey('set_entry_row_$low')));
      expect(row.bottom, lessThanOrEqualTo(keypad.top));
      expect(row.top, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('the rows close up at once under reduced motion', (
      tester,
    ) async {
      final sets = ValueNotifier(plain(3));
      await tester.pumpWidget(host(sets, reduceMotion: true));
      await tester.pumpAndSettle();
      final before = top(tester, find.byKey(sentinel));
      final rowStep =
          top(tester, find.byKey(const ValueKey('set_entry_row_2'))) -
          top(tester, find.byKey(const ValueKey('set_entry_row_1')));
      await deleteFromMenu(tester, 1);
      await tester.pump();
      expect(top(tester, find.byKey(sentinel)), closeTo(before - rowStep, 0.5));
      await tester.pumpAndSettle();
    });
  });

  group('the record mark', () {
    Finder pop(int index) => find.descendant(
      of: find.byKey(ValueKey('live-record-$index')),
      matching: find.byType(ScaleTransition),
    );
    double scale(WidgetTester tester, int index) =>
        tester.widget<ScaleTransition>(pop(index)).scale.value;

    testWidgets('a mark the table opens with is simply there', (tester) async {
      final sets = ValueNotifier([
        const SetEntry(weight: 100, reps: 5, record: true),
        const SetEntry(weight: 90, reps: 5),
      ]);
      await tester.pumpWidget(host(sets));
      await tester.pump();
      expect(scale(tester, 0), 1);
      // Built again from scratch, as a card scrolled back into view is.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host(sets));
      await tester.pump();
      expect(scale(tester, 0), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a mark earned on screen pops in once', (tester) async {
      final semantics = tester.ensureSemantics();
      final sets = ValueNotifier(plain(2));
      await tester.pumpWidget(host(sets));
      await tester.pumpAndSettle();
      sets.value = [
        sets.value.first,
        const SetEntry(weight: 120, reps: 5, record: true),
      ];
      await tester.pump();
      // In the tree and announced with its row from the first frame, growing
      // from nothing.
      expect(find.bySemanticsLabel(RegExp('Personal record')), findsOneWidget);
      expect(scale(tester, 1), lessThan(0.1));
      await tester.pump(AppMotion.enter ~/ 2);
      expect(scale(tester, 1), greaterThan(0.5));
      await tester.pumpAndSettle();
      expect(scale(tester, 1), 1);
      // Another rebuild with the mark still earned doesn't replay it.
      sets.value = [...sets.value];
      await tester.pump();
      expect(scale(tester, 1), 1);
      expect(tester.hasRunningAnimations, isFalse);
      semantics.dispose();
    });

    testWidgets('a mark moved up by a deleted set does not pop again', (
      tester,
    ) async {
      final sets = ValueNotifier([
        ...plain(2),
        const SetEntry(weight: 120, reps: 5, record: true),
      ]);
      await tester.pumpWidget(host(sets));
      await tester.pumpAndSettle();
      await deleteFromMenu(tester, 0);
      await tester.pump();
      expect(find.byKey(const ValueKey('live-record-1')), findsOneWidget);
      expect(scale(tester, 1), 1);
      await tester.pumpAndSettle();
    });

    testWidgets('a mark earned under reduced motion is simply there', (
      tester,
    ) async {
      final sets = ValueNotifier(plain(1));
      await tester.pumpWidget(host(sets, reduceMotion: true));
      await tester.pumpAndSettle();
      sets.value = [const SetEntry(weight: 120, reps: 5, record: true)];
      await tester.pump();
      expect(scale(tester, 0), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  testWidgets('the keypad rises on the quick token, at once under reduced '
      'motion', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final reduceMotion in [false, true]) {
      final sets = ValueNotifier(plain(2));
      await tester.pumpWidget(host(sets, reduceMotion: reduceMotion));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Set 1 Kg'));
      // The slide starts once the two frames after opening are drawn.
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump();
      }
      double offset() =>
          tester
              .widget<FractionalTranslation>(
                find.ancestor(
                  of: find.byType(BottomSheet),
                  matching: find.byType(FractionalTranslation),
                ),
              )
              .translation
              .dy;
      if (reduceMotion) {
        await tester.pump();
        expect(offset(), 0);
      } else {
        await tester.pump(AppMotion.quick ~/ 3);
        expect(offset(), inExclusiveRange(0, 1));
        await tester.pump(AppMotion.quick);
        expect(offset(), 0);
      }
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    semantics.dispose();
  });
}
