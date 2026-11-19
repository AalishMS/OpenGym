import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/underline_tab_strip.dart';

void main() {
  const accent = Color(0xFF7C5CFF);

  Widget host(
    int count,
    int selected, {
    double width = 360,
    ScrollController? controller,
    int? previousIndex,
    bool reduceMotion = false,
  }) {
    return MaterialApp(
      theme: buildTheme(accent, Brightness.dark),
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: UnderlineTabStrip(
              rule: StripRule.top,
              selectedIndex: selected,
              color: accent,
              controller: controller,
              previousIndex: previousIndex,
              tabs: [
                for (var i = 0; i < count; i++)
                  UnderlineTabData(label: 'WEEK ${i + 1}', onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('marks only the selected tab, in the strip colour', (
    tester,
  ) async {
    await tester.pumpWidget(host(4, 2));
    await tester.pumpAndSettle();

    // The colour belongs to the strip rather than to each tab. Plans used to
    // resolve their own, which painted the workout screen in as many hues as
    // there were plans; the mark's job is to say *which tab*, and position
    // already carries that.
    expect(tester.widget<Text>(find.text('WEEK 3')).style?.color, accent);
    for (final label in ['WEEK 1', 'WEEK 2', 'WEEK 4']) {
      expect(tester.widget<Text>(find.text(label)).style?.color, isNot(accent));
    }

    final marks = tester
        .widgetList<Container>(find.byType(Container))
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.border)
        .whereType<Border>()
        .where(
          (border) => border.bottom.width == 2 && border.bottom.color == accent,
        );
    expect(marks, hasLength(1));
  });

  testWidgets('lays out every tab, including those past the viewport', (
    tester,
  ) async {
    await tester.pumpWidget(host(20, 0));
    await tester.pumpAndSettle();

    // Eager layout is the point: a ListView.builder would never build WEEK 20,
    // so there would be nothing for ensureVisible to measure.
    expect(find.text('WEEK 20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gives every tab a 48 pixel hit region', (tester) async {
    await tester.pumpWidget(host(4, 0));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(UnderlineTabStrip)).height,
      greaterThanOrEqualTo(48),
    );
    for (final inkWell in find.byType(InkWell).evaluate()) {
      expect(
        tester.getSize(find.byWidget(inkWell.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
  });

  testWidgets('short strips fill the viewport from the left', (tester) async {
    await tester.pumpWidget(host(2, 0));
    await tester.pumpAndSettle();

    final viewport = tester.getRect(find.byType(UnderlineTabStrip));
    final scrollable = tester.getRect(find.byType(Scrollable));
    expect(scrollable.left, viewport.left);
    expect(scrollable.right, viewport.right);
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      0,
    );
  });

  testWidgets('scrolls a far-off selected tab into view', (tester) async {
    await tester.pumpWidget(host(20, 19));
    await tester.pumpAndSettle();

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.pixels, greaterThan(0));

    final tab = tester.getRect(find.text('WEEK 20'));
    final viewport = tester.getRect(find.byType(UnderlineTabStrip));
    expect(tab.left, greaterThanOrEqualTo(viewport.left));
    expect(tab.right, lessThanOrEqualTo(viewport.right));
  });

  testWidgets('holds its offset when the edge fades turn on', (tester) async {
    await tester.pumpWidget(host(20, 19));
    await tester.pumpAndSettle();
    final settled =
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

    // The fades used to be applied by wrapping the scroll view only when
    // needed, which rebuilt its element and reset the offset to zero.
    await tester.pump();
    await tester.pump();
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      settled,
    );
  });

  testWidgets('follows the selection when it changes', (tester) async {
    await tester.pumpWidget(host(20, 0));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      0,
    );

    await tester.pumpWidget(host(20, 19));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );
  });

  /// The underlines the tabs draw themselves.
  Iterable<Border> ownMarks(WidgetTester tester) => tester
      .widgetList<Container>(find.byType(Container))
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .map((decoration) => decoration.border)
      .whereType<Border>()
      .where(
        (border) => border.bottom.width == 2 && border.bottom.color == accent,
      );

  /// The underline while it slides from one tab to another.
  final slidingMark = find.descendant(
    of: find.byType(UnderlineTabStrip),
    matching: find.byType(Positioned),
  );

  double pixels(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

  testWidgets('a strip taking the place of another starts where it stood and '
      'slides the mark across to the selection', (tester) async {
    final controller = ScrollController(initialScrollOffset: 300);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(20, 10, controller: controller, previousIndex: 9),
    );
    // The first frame is the strip it replaced: scrolled as it was, the mark
    // under the tab that was selected.
    expect(pixels(tester), 300);
    expect(slidingMark, findsNothing);
    expect(ownMarks(tester), hasLength(1));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Partway: one mark, between the two tabs, and the strip easing the
    // selection toward the middle rather than jumping to it.
    expect(ownMarks(tester), isEmpty);
    final mark = tester.getRect(slidingMark);
    final from = tester.getRect(find.text('WEEK 10'));
    final to = tester.getRect(find.text('WEEK 11'));
    final scrolled = pixels(tester) - 300;
    expect(mark.left, inExclusiveRange(from.left - 1, to.left - 1));
    expect(mark.height, 2);
    expect(scrolled, isNot(0));

    await tester.pumpAndSettle();
    expect(slidingMark, findsNothing);
    expect(ownMarks(tester), hasLength(1));
    final tab = tester.getRect(find.text('WEEK 11'));
    final viewport = tester.getRect(find.byType(UnderlineTabStrip));
    expect(tab.center.dx, closeTo(viewport.center.dx, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a strip taking another place lands at once under reduced '
      'motion', (tester) async {
    await tester.pumpWidget(host(4, 2, previousIndex: 1, reduceMotion: true));
    await tester.pump();
    expect(slidingMark, findsNothing);
    expect(ownMarks(tester), hasLength(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('WEEK 3')).style?.color, accent);
  });

  testWidgets('a selection changed in place moves the mark at once', (
    tester,
  ) async {
    await tester.pumpWidget(host(4, 0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(4, 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(slidingMark, findsNothing);
    expect(ownMarks(tester), hasLength(1));
  });
}
