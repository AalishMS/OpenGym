import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/app_button.dart';
import 'package:gymapp/widgets/app_wordmark.dart';

Future<ThemeData> _themeFor(WidgetTester tester) async {
  late ThemeData theme;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(const Color(0xFF00A8FF), Brightness.light),
      home: Builder(
        builder: (context) {
          theme = Theme.of(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return theme;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('interface typography and controls use Manrope roles', (
    tester,
  ) async {
    final theme = await _themeFor(tester);
    final interfaceStyles = <TextStyle?>[
      theme.textTheme.headlineLarge,
      theme.textTheme.headlineMedium,
      theme.textTheme.headlineSmall,
      theme.textTheme.titleLarge,
      theme.textTheme.titleMedium,
      theme.textTheme.titleSmall,
      theme.textTheme.bodyLarge,
      theme.textTheme.bodyMedium,
      theme.textTheme.bodySmall,
      theme.appBarTheme.titleTextStyle,
      theme.dialogTheme.titleTextStyle,
      theme.dialogTheme.contentTextStyle,
      theme.snackBarTheme.contentTextStyle,
      theme.tooltipTheme.textStyle,
    ];

    for (final style in interfaceStyles) {
      expect(style?.fontFamily, startsWith('Manrope'));
    }

    expect(
      theme.elevatedButtonTheme.style?.textStyle?.resolve({})?.fontFamily,
      startsWith('Manrope'),
    );
    expect(
      theme.outlinedButtonTheme.style?.textStyle?.resolve({})?.fontFamily,
      startsWith('Manrope'),
    );
    expect(
      theme.textButtonTheme.style?.textStyle?.resolve({})?.fontFamily,
      startsWith('Manrope'),
    );
  });

  testWidgets('buttons provide primary secondary and tertiary hierarchy', (
    tester,
  ) async {
    final theme = await _themeFor(tester);
    final colors = theme.extension<AppColorScheme>()!;
    final primary = theme.elevatedButtonTheme.style!;
    final secondary = theme.outlinedButtonTheme.style!;
    final tertiary = theme.textButtonTheme.style!;

    expect(primary.backgroundColor?.resolve({}), colors.accentFill);
    expect(primary.foregroundColor?.resolve({}), colors.onAccent);
    expect(secondary.backgroundColor?.resolve({}), isNull);
    expect(secondary.foregroundColor?.resolve({}), colors.textPrimary);
    expect(secondary.side?.resolve({})?.color, colors.border);
    expect(tertiary.backgroundColor?.resolve({}), isNull);
    expect(tertiary.foregroundColor?.resolve({}), colors.accent);
  });

  testWidgets('controls expose interaction states and 48 pixel tap regions', (
    tester,
  ) async {
    final theme = await _themeFor(tester);
    final styles = <ButtonStyle>[
      theme.elevatedButtonTheme.style!,
      theme.outlinedButtonTheme.style!,
      theme.textButtonTheme.style!,
    ];

    for (final style in styles) {
      expect(style.minimumSize?.resolve({}), const Size(48, 48));
      expect(
        style.foregroundColor?.resolve({WidgetState.disabled}),
        isNot(style.foregroundColor?.resolve({})),
      );
      for (final state in [
        WidgetState.focused,
        WidgetState.hovered,
        WidgetState.pressed,
      ]) {
        expect(style.overlayColor?.resolve({state}), isNotNull);
      }
    }

    expect(
      theme.iconButtonTheme.style?.minimumSize?.resolve({}),
      const Size(48, 48),
    );
  });

  testWidgets('desktop adaptive density keeps rendered controls at least 48', (
    tester,
  ) async {
    final keys = List.generate(4, (index) => Key('control-$index'));
    final theme = buildTheme(
      const Color(0xFF00A8FF),
      Brightness.light,
    ).copyWith(
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElevatedButton(
                key: keys[0],
                onPressed: () {},
                child: const Text('Go'),
              ),
              OutlinedButton(
                key: keys[1],
                onPressed: () {},
                child: const Text('Go'),
              ),
              TextButton(
                key: keys[2],
                onPressed: () {},
                child: const Text('Go'),
              ),
              IconButton(
                key: keys[3],
                onPressed: () {},
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
    );

    for (final key in keys) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(48), reason: '$key width');
      expect(size.height, greaterThanOrEqualTo(48), reason: '$key height');
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('wordmark and shared buttons render in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(const Color(0xFF00A8FF), brightness),
          home: Scaffold(
            body: Column(
              children: [
                const AppWordmark(),
                AppButton.primary(label: 'Save', onPressed: () {}),
                AppButton.secondary(label: 'Cancel', onPressed: () {}),
                AppButton.text(label: 'New plan', onPressed: () {}),
                AppButton.destructive(label: 'Delete', onPressed: () {}),
              ],
            ),
          ),
        ),
      );

      expect(find.text('> OpenGym'), findsOneWidget);
      for (final label in ['Save', 'Cancel', 'New plan', 'Delete']) {
        expect(find.text(label), findsOneWidget);
        expect(find.text('[$label]'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('destructive and icon actions expose all interaction states', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF00A8FF), Brightness.light),
        home: Scaffold(
          body: Row(
            children: [
              AppButton.destructive(label: 'Delete', onPressed: () {}),
              AppIconButton(
                label: 'More options',
                icon: Icons.more_horiz,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    final destructive = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Delete'),
    );
    for (final state in [
      WidgetState.focused,
      WidgetState.hovered,
      WidgetState.pressed,
    ]) {
      expect(destructive.style?.overlayColor?.resolve({state}), isNotNull);
    }
    expect(find.byTooltip('More options'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('More options')).height, 48);
  });
}
