import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/underline_tab_strip.dart';

void main() {
  Widget host(int count, int selected, {double width = 360}) {
    return MaterialApp(
      theme: buildTheme(const Color(0xFF7C5CFF), Brightness.dark),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: UnderlineTabStrip(
              rule: StripRule.top,
              selectedIndex: selected,
              tabs: [
                for (var i = 0; i < count; i++)
                  UnderlineTabData(
                    label: 'WEEK ${i + 1}',
                    color: const Color(0xFF7C5CFF),
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('lays out every tab, including those past the viewport',
      (tester) async {
    await tester.pumpWidget(host(20, 0));
    await tester.pumpAndSettle();

    // Eager layout is the point: a ListView.builder would never build WEEK 20,
    // so there would be nothing for ensureVisible to measure.
    expect(find.text('WEEK 20'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
}
