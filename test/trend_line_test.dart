import 'package:flutter_test/flutter_test.dart';

import 'package:gymapp/widgets/statistics/trend_line.dart';

void main() {
  test('axis ceilings round up to a readable figure', () {
    expect(niceAxisCeiling(0), 1);
    expect(niceAxisCeiling(-5), 1);
    expect(niceAxisCeiling(1), 1);
    expect(niceAxisCeiling(14.4), 15);
    expect(niceAxisCeiling(20317), 25000);
    expect(niceAxisCeiling(31500), 40000);
    expect(niceAxisCeiling(0.3), closeTo(0.3, 1e-12));
    expect(niceAxisCeiling(8100), 10000);
    for (final value in [0.7, 3.3, 47.0, 999.0, 123456.0]) {
      final ceiling = niceAxisCeiling(value);
      expect(ceiling, greaterThanOrEqualTo(value));
      // The tallest mark keeps at least two thirds of the plot.
      expect(value / ceiling, greaterThan(0.66));
    }
  });
}
