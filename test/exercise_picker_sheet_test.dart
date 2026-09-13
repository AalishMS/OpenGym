import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/spacing.dart';
import 'package:gymapp/widgets/exercise_picker_sheet.dart';

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

  Future<void> pumpPicker(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    double keyboardInset = 0,
    Brightness brightness = Brightness.light,
    List<String> initialNames = const [],
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
              ),
              child: child!,
            ),
        home: _PickerHarness(initialNames: initialNames),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
  }

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
