import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gymapp/models/statistics.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/statistics/block_statistics.dart';
import 'package:gymapp/widgets/statistics/block_trend.dart';

import 'support/test_fonts.dart';

BlockStatistics block(
  int i, {
  bool zero = false,
  bool noWeeks = false,
  bool longName = false,
}) => BlockStatistics(
  block: TrainingBlock(
    id: '$i',
    splitId: 'test',
    name:
        longName
            ? 'Progressive strength and conditioning block ${i + 1}'
            : 'Block ${i + 1}',
    position: i,
    createdAt: DateTime(2026),
    plannedWeekCount: 4,
  ),
  weeks:
      noWeeks
          ? []
          : [
            for (var n = 1; n <= 2; n++)
              BlockWeekStatistics(
                weekId: '$i-$n',
                number: n,
                workouts: zero ? 0 : 2,
                sets: zero ? 0 : (i + 1) * 10,
                volumeLoad: zero ? 0 : (i + 1) * 500,
              ),
            const BlockWeekStatistics(weekId: null, number: 3),
            const BlockWeekStatistics(weekId: null, number: 4),
          ],
  workouts: zero ? 0 : 4,
  sets: zero ? 0 : (i + 1) * 20,
  volumeLoad: zero ? 0 : (i + 1) * 1000,
  records: zero ? 0 : (i + 1) * 2,
  firstDate: DateTime(2026, 1, 1),
  lastDate: DateTime(2026, 1, 14),
  latestWeekId: noWeeks ? null : '$i-2',
  gains:
      zero
          ? []
          : [
            LiftGain(exerciseName: 'Bench press', start: 80, end: 90 + i * 2.5),
          ],
);

void main() {
  setUpAll(loadTestFonts);

  Widget host(
    List<BlockStatistics> blocks, {
    double scale = 1,
    Brightness brightness = Brightness.light,
    String unit = 'kg',
  }) {
    var selected = blocks.last;
    return MaterialApp(
      theme: buildTheme(const Color(0xFF41B9B9), brightness),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: StatefulBuilder(
            builder:
                (context, setState) => SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: BlockOverview(
                    blocks: blocks,
                    selected: selected,
                    currentBlockId: blocks.last.block.id,
                    weightUnit: unit,
                    onSelect:
                        (id) => setState(
                          () =>
                              selected = blocks.firstWhere(
                                (block) => block.block.id == id,
                              ),
                        ),
                  ),
                ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'long block timelines browse, select and retain position across measures',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host([for (var i = 0; i < 10; i++) block(i)]));
      await tester.pumpAndSettle();
      final plot = find.byKey(const ValueKey('block-trend-scroll'));
      final scrollable = find.descendant(
        of: plot,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.pixels, 0);
      expect(find.text('5,000 kg'), findsOneWidget);
      await tester.drag(plot, const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      await tester.tap(find.byKey(const ValueKey('block-point-4')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('block-overview-name')))
            .data,
        'Block 5',
      );
      expect(find.text('2,500 kg'), findsOneWidget);
      final offset = position.pixels;
      await tester.tap(
        find.byKey(ValueKey('block-measure-${BlockTrendMeasure.records}')),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, offset);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('block-trend-value')))
            .data,
        '5',
      );
      final point = tester.getSemantics(
        find.byKey(const ValueKey('block-point-4')),
      );
      expect(point.label, contains('Records, 5, per trained week'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'units and averaging stay explicit; weeks and gains reveal exact details',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host([block(0)], unit: 'lbs'));
      await tester.pumpAndSettle();
      expect(find.text('1,102.31 lbs'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('block-basis')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block total'));
      await tester.pumpAndSettle();
      expect(find.text('2,204.62 lbs'), findsOneWidget);
      final week = find.byKey(const ValueKey('block-week-3'));
      await tester.ensureVisible(week);
      await tester.tap(week);
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('block-week-readout')))
            .data,
        'Week 3  /  Not started',
      );
      final gain = find.byKey(const ValueKey('block-gain-Bench press'));
      await tester.ensureVisible(gain);
      await tester.tap(gain);
      await tester.pumpAndSettle();
      expect(find.text('176.4 lbs to 198.4 lbs'), findsOneWidget);
      await tester.tap(gain);
      await tester.pump();
      expect(find.text('176.4 lbs to 198.4 lbs'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'single, flat and empty-workload blocks handle small screens and 2x text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 2.0]) {
          for (final data in [
            [block(0, zero: true, noWeeks: true)],
            [block(0), block(0).copyForTest('other')],
            [block(0, longName: true)],
          ]) {
            await tester.pumpWidget(
              host(data, brightness: brightness, scale: scale),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$brightness $scale',
            );
            expect(find.textContaining('NaN'), findsNothing);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    },
  );
}

extension on BlockStatistics {
  BlockStatistics copyForTest(String id) => BlockStatistics(
    block: this.block.copyWith(id: id, name: 'Another block'),
    weeks: weeks,
    workouts: workouts,
    sets: sets,
    volumeLoad: volumeLoad,
    records: records,
    firstDate: firstDate,
    lastDate: lastDate,
    latestWeekId: latestWeekId,
    gains: gains,
  );
}
