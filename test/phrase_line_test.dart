import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gymapp/widgets/phrase_line.dart';

void main() {
  // The test font's glyphs are squares one font size wide.
  const style = TextStyle(fontSize: 10, height: 1);

  Widget host(double width) => MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: PhraseLine.text(const ['ab cd', 'ef'], style: style),
      ),
    ),
  );

  testWidgets('with room, the dot follows the phrase on its line', (
    tester,
  ) async {
    await tester.pumpWidget(host(400));
    final phrase = tester.getRect(find.text('ab cd'));
    final dot = tester.getRect(find.text(' · '));
    expect(dot.left, phrase.right);
    expect(tester.getTopLeft(find.text('ef')).dx, dot.right);
    expect(tester.getTopLeft(find.text('ef')).dy, phrase.top);
  });

  testWidgets('a phrase gets the whole line before its dot', (tester) async {
    await tester.pumpWidget(host(400));
    final phraseWidth = tester.getSize(find.text('ab cd')).width;
    final dotWidth = tester.getSize(find.text(' · ')).width;

    // Wide enough for the phrase, not for the phrase and its dot: the phrase
    // keeps its one line rather than giving the dot room and breaking, and
    // the next phrase starts the next line.
    await tester.pumpWidget(host(phraseWidth + dotWidth / 2));
    expect(tester.getSize(find.text('ab cd')).height, 10);
    expect(tester.getTopLeft(find.text('ef')).dx, 0);
    expect(tester.getTopLeft(find.text('ef')).dy, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
