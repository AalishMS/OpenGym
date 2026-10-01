import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/utils/plan_stats.dart';
import 'package:gymapp/widgets/home/plan_card.dart';
import 'package:gymapp/widgets/home/plan_grid.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  List<WorkoutPlan> plans() => [
    for (final name in ['Push', 'Pull', 'Legs', 'Upper', 'Lower'])
      WorkoutPlan(
        id: name,
        name: name,
        exercises: [ExerciseTemplate(name: 'Bench Press', sets: 3)],
      ),
  ];

  Finder card(String id) => find.byWidgetPredicate(
    (widget) => widget is PlanCard && widget.plan.id == id,
  );

  Widget host({
    required List<WorkoutPlan> values,
    required void Function(String, String) onMove,
    bool reducedMotion = false,
    double textScale = 1,
    TextDirection direction = TextDirection.ltr,
    Brightness brightness = Brightness.light,
    ValueChanged<int>? onOpen,
    Map<int, PlanStat> stats = const {},
  }) => MaterialApp(
    theme: buildTheme(const Color(0xFF00A8FF), brightness),
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: reducedMotion,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: PlanGrid(
              plans: values,
              stats: stats,
              onOpen: onOpen ?? (_) {},
              onShowActions: (_) {},
              onMove: onMove,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('cards animate across rows and can be tapped after settling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    addTearDown(tester.view.reset);
    var values = plans();
    int? opened;
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return host(
            values: values,
            onMove: (_, _) {},
            onOpen: (index) => opened = index,
          );
        },
      ),
    );
    final start = tester.getTopLeft(card('Push'));
    final destination = tester.getTopLeft(card('Upper'));
    update(() {
      values =
          List.of(values)
            ..removeAt(0)
            ..insert(3, values.first);
    });
    await tester.pump();
    expect(tester.getTopLeft(card('Push')), start);
    await tester.pump(const Duration(milliseconds: 140));
    final middle = tester.getTopLeft(card('Push'));
    expect(middle.dy, greaterThan(start.dy));
    expect(middle.dy, lessThan(destination.dy));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(card('Push')), destination);
    await tester.tap(card('Push'));
    expect(opened, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second move or rollback continues from the visible position', (
    tester,
  ) async {
    final original = plans().take(3).toList();
    var values = original;
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return host(values: values, onMove: (_, _) {});
        },
      ),
    );
    final start = tester.getTopLeft(card('Push'));
    update(() => values = [original[1], original[2], original[0]]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final middle = tester.getTopLeft(card('Push'));
    expect(middle, isNot(start));
    update(() => values = original);
    await tester.pump();
    expect(tester.getTopLeft(card('Push')), middle);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(card('Push')), start);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new reorder rebases cards whose destination stays the same', (
    tester,
  ) async {
    final original = plans().take(3).toList();
    var values = original;
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return host(values: values, onMove: (_, _) {});
        },
      ),
    );
    final destination = tester.getTopLeft(card('Push'));
    update(() => values = [original[1], original[2], original[0]]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final middle = tester.getTopLeft(card('Pull'));
    update(() => values = [original[1], original[0], original[2]]);
    await tester.pump();
    expect(tester.getTopLeft(card('Pull')), middle);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(card('Pull')), destination);
  });

  testWidgets('a drag preview preserves the stretched row height', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1040, 800);
    addTearDown(tester.view.reset);
    final values = plans().take(2).toList();
    final recent = PlanStat(
      plan: values.first,
      planIndex: 0,
      sessionCount: 1,
      lastTrained: DateTime.now(),
      volumeKg: 0,
    );
    // Measure both cards without row stretching to prove this fixture needs it.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF00A8FF), Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(0.8)),
          child: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < values.length; index++)
                  SizedBox(
                    width: 495,
                    child: PlanCard(
                      plan: values[index],
                      index: index,
                      stat: index == 0 ? recent : null,
                      onOpen: () {},
                      onShowActions: () {},
                      reorderHandle: const SizedBox(width: 48, height: 48),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(card('Push')).height,
      lessThan(tester.getSize(card('Pull')).height),
    );
    await tester.pumpWidget(
      host(
        values: values,
        stats: {0: recent},
        textScale: 0.8,
        onMove: (_, _) {},
      ),
    );
    final size = tester.getSize(card('Push'));
    expect(tester.getSize(card('Pull')).height, size.height);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Drag to reorder Push')),
    );
    await gesture.moveBy(const Offset(0, 30));
    await tester.pumpAndSettle();
    expect(tester.getSize(card('Push').last), size);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion places reordered cards immediately', (
    tester,
  ) async {
    var values = plans().take(2).toList();
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return host(values: values, reducedMotion: true, onMove: (_, _) {});
        },
      ),
    );
    final destination = tester.getTopLeft(card('Pull'));
    update(() => values = values.reversed.toList());
    await tester.pump();
    expect(tester.getTopLeft(card('Push')), destination);
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.getTopLeft(card('Push')), destination);
  });

  testWidgets('drag previews the full card and cancellation preserves order', (
    tester,
  ) async {
    final values = plans().take(2).toList();
    var moves = 0;
    await tester.pumpWidget(host(values: values, onMove: (_, _) => moves++));
    final originalRect = tester.getRect(card('Push'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Drag to reorder Push')),
    );
    await gesture.moveBy(const Offset(0, 30));
    await tester.pumpAndSettle();
    expect(card('Push'), findsNWidgets(2));
    expect(tester.getSize(card('Push').last), originalRect.size);
    final sourceOpacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: card('Push').first,
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(sourceOpacity.opacity, 0.3);
    await gesture.moveTo(const Offset(5, 5));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(moves, 0);
    expect(card('Push'), findsOneWidget);
    expect(tester.getRect(card('Push')), originalRect);
  });

  testWidgets('hover leaves target geometry stable and drop commits once', (
    tester,
  ) async {
    final values = plans().take(2).toList();
    final moves = <(String, String)>[];
    await tester.pumpWidget(
      host(values: values, onMove: (from, to) => moves.add((from, to))),
    );
    final targetRect = tester.getRect(card('Pull'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Drag to reorder Push')),
    );
    await gesture.moveTo(tester.getCenter(card('Pull')));
    await tester.pumpAndSettle();
    expect(moves, isEmpty);
    expect(tester.getRect(card('Pull')), targetRect);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(moves, [('Push', 'Pull')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text, both themes, RTL and resizing keep cards readable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final values = plans();
    for (final brightness in Brightness.values) {
      for (final width in [1100.0, 740.0, 320.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpWidget(
          host(
            values: values,
            textScale: 2,
            direction: TextDirection.rtl,
            brightness: brightness,
            onMove: (_, _) {},
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final rects =
            values.map((plan) => tester.getRect(card(plan.id!))).toList();
        for (final rect in rects) {
          expect(rect.left, greaterThanOrEqualTo(20));
          expect(rect.right, lessThanOrEqualTo(width - 20));
        }
        if (width == 1100) {
          expect(rects[0].height, rects[1].height);
          expect(rects[0].left, greaterThan(rects[1].left));
        }
      }
    }
  });
}
