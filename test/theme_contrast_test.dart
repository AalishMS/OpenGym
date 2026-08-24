/// Contrast guards for the derived colour system.
///
/// The old palette was fourteen hand-picked accent hexes, ten plan hexes and six
/// RPE hexes, each of which had to be independently lucky against four grounds.
/// Most weren't, and nothing caught it, because a hex cannot be wrong on its own
/// — only wrong *against something*. These tests are that something. They assert
/// the promises `app_theme.dart` makes in its role table, for every accent in
/// both modes, so a failing combination becomes a red test instead of a screen
/// someone eventually squints at.
///
/// Every ratio here would fail on the pre-rewrite palette; see the legacy group
/// at the bottom, which pins the specific bug that started this.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymapp/data/plan_colors.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/semantic_colors.dart';
import 'package:gymapp/theme/tones.dart';

/// Solved tones quantise to 8 bits per channel, which can shave a hair off a
/// ratio that is mathematically exact. Allow that much and no more — this is
/// rounding slack, not a softened target.
const double _quantisationSlack = 0.02;

void _expectContrast(
  Color a,
  Color b, {
  required double atLeast,
  required String what,
}) {
  final ratio = contrastRatio(a, b);
  expect(
    ratio,
    greaterThanOrEqualTo(atLeast - _quantisationSlack),
    reason: '$what scored ${ratio.toStringAsFixed(2)}:1, needs $atLeast:1',
  );
}

/// Pumps a themed app and hands back a [BuildContext] inside it, so the
/// context-taking accessors (`surfaceColor`, `rpeColor`, `planSwatch`) can be
/// tested through the same path widgets use rather than a reimplementation.
Future<BuildContext> _contextFor(
  WidgetTester tester,
  Color seed,
  Brightness brightness,
) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(seed, brightness),
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  setUpAll(() {
    // `buildTheme` builds a TextTheme, which resolves JetBrains Mono through
    // google_fonts — and google_fonts fetches over HTTP when the font is not
    // bundled. A test runner has no network, and the request failing *after* the
    // test body completes fails the test for a reason unrelated to any
    // assertion here. Nothing below is about glyphs, so fall back to the default
    // font rather than reaching for the network.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('accent roles meet their targets', () {
    for (final brightness in Brightness.values) {
      for (final accent in SettingsProvider.accents) {
        test('${accent.name} / ${brightness.name}', () {
          final scheme = deriveColorScheme(accent.seed, brightness);

          // The text accent is solved against the worse of the two grounds, so
          // it has to clear 4.5:1 on *both*. This is the assertion light mode
          // used to fail outright: it drew the dark hexes, CYAN at 1.79:1.
          _expectContrast(scheme.accent, scheme.background,
              atLeast: 4.5, what: '${accent.name} accent on background');
          _expectContrast(scheme.accent, scheme.surface,
              atLeast: 4.5, what: '${accent.name} accent on surface');

          // A fill only needs its edge to read, but it must read on both grounds
          // too — a filled button sits on the page and inside cards.
          _expectContrast(scheme.accentFill, scheme.background,
              atLeast: 3.0, what: '${accent.name} accentFill on background');

          // The pairing that broke on 10 of 14 legacy variants.
          _expectContrast(scheme.onAccent, scheme.accentFill,
              atLeast: 4.5, what: '${accent.name} onAccent on accentFill');
        });
      }
    }
  });

  group('neutrals separate', () {
    // Neutral tones are accent-independent, but they are solved inside the same
    // pass as the accent, so they are re-checked per accent to catch any future
    // coupling. One representative accent is enough to state the targets.
    for (final brightness in Brightness.values) {
      test('surface, border and text / ${brightness.name}', () {
        final scheme =
            deriveColorScheme(SettingsProvider.accents.first.seed, brightness);
        final isDark = brightness == Brightness.dark;

        // A card's fill is a perceptual step off the page rather than a contrast
        // target — see `_surfLiftDark` in app_theme.dart. Assert the step, since
        // that is what the design actually specifies now.
        final lift =
            (oklchOf(scheme.surface).l - oklchOf(scheme.background).l).abs();
        expect(
          lift,
          closeTo(isDark ? 0.075 : 0.061, 0.002),
          reason: 'card fill sits ${lift.toStringAsFixed(3)} off the page in '
              '${brightness.name} mode',
        );

        // …with a ratio floor underneath it regardless, because the bug this
        // replaced was cards at 1.10:1 dark / 1.08:1 light — invisible. Keeping
        // the old metric as a floor means no future change of metric can quietly
        // land back there.
        _expectContrast(scheme.surface, scheme.background,
            atLeast: 1.15, what: 'surface on background');

        // The border is still solved as a ratio: it is a line to be *seen*, and
        // at 3:1 it is also what makes an unfilled text field findable
        // (WCAG 1.4.11), since `inputDecorationTheme` draws it.
        _expectContrast(scheme.border, scheme.surface,
            atLeast: isDark ? 3.0 : 1.90, what: 'border on surface');
        _expectContrast(scheme.textPrimary, scheme.background,
            atLeast: 13.0, what: 'textPrimary on background');
        _expectContrast(scheme.textSecondary, scheme.surface,
            atLeast: 4.5, what: 'textSecondary on surface');
      });
    }

    test('neither mode separates its cards much harder than the other', () {
      // The defect that made dark mode read grey: both modes were handed a
      // contrast *number* (1.45 dark, 1.20 light), and near black a number buys
      // ~2.4× the perceptual step, so dark cards landed on #2F2F2F — a grey box
      // on a black page, tiled across the whole workout screen. Whatever the
      // targets become, the two modes have to stay comparable to the eye.
      double liftFor(Brightness brightness) {
        final scheme =
            deriveColorScheme(SettingsProvider.accents.first.seed, brightness);
        return (oklchOf(scheme.surface).l - oklchOf(scheme.background).l).abs();
      }

      final dark = liftFor(Brightness.dark);
      final light = liftFor(Brightness.light);
      expect(
        math.max(dark, light) / math.min(dark, light),
        lessThan(1.5),
        reason: 'card lift is ${dark.toStringAsFixed(3)} dark vs '
            '${light.toStringAsFixed(3)} light',
      );
    });
  });

  group('semantic colours are legible as text and as grounds', () {
    for (final brightness in Brightness.values) {
      test('error and success / ${brightness.name}', () {
        final scheme =
            deriveColorScheme(SettingsProvider.accents.first.seed, brightness);

        for (final entry in {
          'error': scheme.error,
          'success': scheme.success,
        }.entries) {
          // Read as text on a card…
          _expectContrast(entry.value, scheme.surface,
              atLeast: 4.5, what: '${entry.key} on surface');
          // …and carry a label when used as a ground, which both are (a filled
          // delete button, the [PR] badge).
          _expectContrast(onColor(entry.value), entry.value,
              atLeast: 4.5, what: 'onColor(${entry.key}) on ${entry.key}');
        }
      });
    }
  });

  group('the heatmap ramp climbs', () {
    // Even *perceptual* steps, not even contrast steps — see toneBetween. What
    // must hold is monotonicity: three intensities that a reader can order.
    for (final brightness in Brightness.values) {
      for (final accent in SettingsProvider.accents) {
        test('${accent.name} / ${brightness.name}', () {
          final scheme = deriveColorScheme(accent.seed, brightness);
          final ramp = [
            scheme.background,
            scheme.accentMuted,
            scheme.accentDim,
            scheme.accentFill,
          ];
          for (var i = 1; i < ramp.length; i++) {
            final step = contrastRatio(ramp[i], scheme.background);
            final previous = contrastRatio(ramp[i - 1], scheme.background);
            expect(
              step,
              greaterThan(previous),
              reason: '${accent.name} ${brightness.name}: heatmap step $i '
                  '(${step.toStringAsFixed(2)}:1) does not exceed step '
                  '${i - 1} (${previous.toStringAsFixed(2)}:1)',
            );
          }
        });
      }
    }
  });

  group('plan colours', () {
    for (final brightness in Brightness.values) {
      testWidgets('all ${kPlanColors.length} slots / ${brightness.name}',
          (tester) async {
        final context = await _contextFor(
            tester, SettingsProvider.accents.first.seed, brightness);
        final surface = surfaceColor(context);

        for (var slot = 0; slot < kPlanColors.length; slot++) {
          final resolved = planSwatch(slot, context);
          // Plan colours label cards and draw stripes on them. All ten used to
          // score 1.53–3.44 on the light background because there were no light
          // variants at all.
          _expectContrast(resolved, surface,
              atLeast: 4.5, what: 'plan slot $slot on surface');
          _expectContrast(onColor(resolved), resolved,
              atLeast: 4.5, what: 'onColor(plan slot $slot) on itself');
        }
      });

      testWidgets('stored values map back to a slot / ${brightness.name}',
          (tester) async {
        final context = await _contextFor(
            tester, SettingsProvider.accents.first.seed, brightness);

        // Plans persist a raw ARGB value, so a legacy hex has to land on the
        // nearest hue rather than needing a Hive migration. Every value the
        // picker can write must round-trip to the slot that wrote it, or the
        // picker stops highlighting the user's own choice.
        for (var slot = 0; slot < kPlanColors.length; slot++) {
          expect(planSlotOf(kPlanColors[slot]), slot,
              reason: 'slot $slot did not round-trip through planSlotOf');
        }

        // A null plan colour means "inherit the accent", not "transparent".
        expect(planColorOf(null, context), accentColor(context));
      });
    }
  });

  group('the RPE ramp', () {
    for (final brightness in Brightness.values) {
      testWidgets('every step is legible / ${brightness.name}',
          (tester) async {
        final context = await _contextFor(
            tester, SettingsProvider.accents.first.seed, brightness);
        final surface = surfaceColor(context);

        // All six RPE values, not just the six distinct steps: the thresholds
        // are part of the contract.
        for (var rpe = 1; rpe <= 10; rpe++) {
          _expectContrast(rpeColor(rpe, context), surface,
              atLeast: 4.5, what: 'RPE $rpe on surface');
        }
      });

      testWidgets('reads as a progression of hue / ${brightness.name}',
          (tester) async {
        final context = await _contextFor(
            tester, SettingsProvider.accents.first.seed, brightness);

        // The ramp's meaning is carried by hue. Distinct tones for distinct
        // bands is the minimum: six shades of pale (which is what light mode
        // used to show) conveys nothing.
        final distinct = {
          for (final rpe in [1, 3, 5, 7, 9, 10])
            rpeColor(rpe, context).toARGB32()
        };
        expect(distinct.length, 6,
            reason: 'RPE bands collapsed into ${distinct.length} colours');
      });
    }
  });

  group('onAccent is only ever painted on accentFill', () {
    // The value-level promise (`onAccent` reads on `accentFill`) is asserted
    // above. This group asserts the *usage* half, which no colour arithmetic can
    // reach: that the ground a widget actually paints is the one `onAccent` was
    // solved against. Mixing them is silent — both tokens exist, both compile,
    // and the result is a label at 3.63:1 in light mode on every accent.
    //
    // Why a source scan rather than a widget test: the rule is a property of ~25
    // call sites across 8 files, and a widget test per site would assert the
    // colours a widget was handed, not that the next filled button someone adds
    // reaches for the right token.

    /// Grounds that must never appear under an `onAccent` foreground, spelled as
    /// the app spells them. `accent` is the text/line role: solved for 4.5:1 as
    /// *ink*, which makes it darker than the fill in light mode, so the
    /// black-ish `onAccent` lands on a dark ground and neither reads.
    ///
    /// Only the two spellings that make a colour a *ground* count. `color:`
    /// alone is ambiguous — it paints a `Text`, an `Icon` and a `BorderSide`
    /// just as often as a `BoxDecoration` — so a bare `color: accent` is matched
    /// only when it is not obviously a line or a glyph, checked below.
    final ground = RegExp(
      r'(backgroundColor:|color:)\s*'
      r'(accent|accentColor\(context\))\s*[,)]',
    );

    /// The two things `accent` is *supposed* to colour. A border is a hairline
    /// and an icon or a label is ink; neither is a surface anything sits on, so
    /// neither can be the wrong half of a pairing.
    final lineOrInk = RegExp(r'Border|BorderSide|Icon\(|Text\(|style:|Divider');

    /// The measured failure the ban encodes, so the number in the comments is
    /// checked rather than remembered.
    test('the banned pairing really does fail, on every accent', () {
      for (final accent in SettingsProvider.accents) {
        final scheme = deriveColorScheme(accent.seed, Brightness.light);
        final wrong = contrastRatio(scheme.onAccent, scheme.accent);
        final right = contrastRatio(scheme.onAccent, scheme.accentFill);
        expect(wrong, lessThan(4.5),
            reason: '${accent.name}: onAccent on accent scored '
                '${wrong.toStringAsFixed(2)}:1 — if this now passes, the ban '
                'below is obsolete and should be reconsidered, not deleted');
        expect(right, greaterThan(wrong));
      }
    });

    test('no widget paints onAccent on the text accent', () {
      final offenders = <String>[];

      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          // The theme layer is where the roles are defined and where the
          // Material ColorScheme maps `primary: accent` with a matching
          // `onColor(accent)`. That pairing solves against its own ground, so
          // it is correct by construction and exempt.
          .where((f) => !f.path.contains('theme'))) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!ground.hasMatch(lines[i])) continue;
          if (lineOrInk.hasMatch(lines[i])) continue;

          // A ground is only wrong if something asks for `onAccent` on top of
          // it. Look ahead for the foreground the same widget declares — far
          // enough to clear a `BoxDecoration`'s border and radius, close enough
          // not to reach the next widget.
          final window =
              lines.sublist(i, (i + 12).clamp(0, lines.length)).join('\n');
          if (window.contains('onAccentColor(context)')) {
            offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'These sites pair an `accent` ground with an `onAccent` '
            'foreground. Use `accentFillColor(context)` as the ground:\n'
            '${offenders.join('\n')}',
      );
    });

    test('the scan can still see a violation', () {
      // A guard that only ever passes is indistinguishable from a guard that
      // matches nothing. Re-run the same two regexes over the shape this group
      // exists to ban, and over the three shapes it must tolerate.
      const violation = '''
              decoration: BoxDecoration(
                color: accent,
                borderRadius: AppRadius.button,
              ),
              child: Text('[SAVE]',
                  style: TextStyle(color: onAccentColor(context))),''';
      const allowed = [
        "Icon(LucideIcons.plus, size: 12, color: accent),\n"
            "Text('x', style: TextStyle(color: onAccentColor(context)))",
        "border: Border.all(color: accent, width: 1),\n"
            "child: Text('x', style: TextStyle(color: onAccentColor(context)))",
        "color: accentFillColor(context),\n"
            "child: Text('x', style: TextStyle(color: onAccentColor(context)))",
      ];

      bool flags(String source) {
        final lines = source.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (!ground.hasMatch(lines[i])) continue;
          if (lineOrInk.hasMatch(lines[i])) continue;
          if (lines
              .sublist(i, (i + 12).clamp(0, lines.length))
              .join('\n')
              .contains('onAccentColor(context)')) {
            return true;
          }
        }
        return false;
      }

      expect(flags(violation), isTrue,
          reason: 'the scan no longer detects the bug it was written for');
      for (final source in allowed) {
        expect(flags(source), isFalse, reason: 'false positive on: $source');
      }
    });
  });

  group('bestForeground beats the luminance > 0.5 rule it replaced', () {
    // The pre-rewrite accent pairs, kept here as data rather than in the app:
    // this group exists to pin the bug, so it must keep testing the values the
    // bug was found on even though nothing paints them any more.
    const legacy = <String, List<Color>>{
      'ELECTRIC BLUE': [Color(0xFF00A8FF), Color(0xFF0077CC)],
      'WARM AMBER': [Color(0xFFFF9500), Color(0xFFCC7700)],
      'DEEP ORANGE': [Color(0xFFFF5722), Color(0xFFE64A19)],
      'HOT PINK': [Color(0xFFFF1493), Color(0xFFCC1177)],
      'CYAN': [Color(0xFF00CED1), Color(0xFF00A5A8)],
      'PURPLE': [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
      'STEEL GRAY': [Color(0xFFA0A0A0), Color(0xFF666666)],
    };

    /// The rule this replaced: white on anything darker than mid-luminance.
    Color oldRule(Color ground) => ground.computeLuminance() > 0.5
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);

    test('never scores worse, and fixes 10 of the 14 variants', () {
      var improved = 0;
      legacy.forEach((name, variants) {
        for (final variant in variants) {
          final now = contrastRatio(bestForeground(variant), variant);
          final before = contrastRatio(oldRule(variant), variant);
          expect(now, greaterThanOrEqualTo(before),
              reason: '$name ${variant.toARGB32().toRadixString(16)}: '
                  'bestForeground (${now.toStringAsFixed(2)}) is worse than '
                  'the old rule (${before.toStringAsFixed(2)})');
          if (now > before) improved++;
        }
      });
      expect(improved, 10);
    });

    test('CYAN dark is the case that started this', () {
      const cyan = Color(0xFF00CED1);
      expect(contrastRatio(oldRule(cyan), cyan), lessThan(2.0));
      expect(contrastRatio(bestForeground(cyan), cyan), greaterThan(10.0));
    });

    test('the crossover is 0.179, not 0.5', () {
      // Two greys straddling the *true* crossover, both well under 0.5 — so the
      // old rule handed white to each. Only the darker one deserved it.
      const aboveCrossover = Color(0xFF898989); // luminance ~0.25
      const belowCrossover = Color(0xFF616161); // luminance ~0.12

      expect(bestForeground(aboveCrossover), const Color(0xFF000000));
      expect(oldRule(aboveCrossover), const Color(0xFFFFFFFF));

      expect(bestForeground(belowCrossover), const Color(0xFFFFFFFF));
      expect(oldRule(belowCrossover), const Color(0xFFFFFFFF));

      // Whatever the ground, the better of black and white always clears AA —
      // which is why `onColor` can be a total function with no fallback.
      for (var v = 0; v < 256; v += 5) {
        final grey = Color.fromARGB(255, v, v, v);
        expect(contrastRatio(bestForeground(grey), grey),
            greaterThanOrEqualTo(4.5));
      }
    });
  });
}
