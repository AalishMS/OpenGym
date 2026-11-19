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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymapp/data/plan_colors.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/semantic_colors.dart';
import 'package:gymapp/theme/tones.dart';
import 'package:gymapp/widgets/home/training_snapshot.dart';
import 'package:gymapp/widgets/raised_card.dart';

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
      // A fresh app per call: reusing the element would animate the theme in
      // from the previous call's, and the first frame would read that one.
      key: UniqueKey(),
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

/// The three grounds anything can be drawn on, by name, as widgets see them.
Map<String, Color> _grounds(BuildContext context) => {
  'page': backgroundColor(context),
  'surface': surfaceColor(context),
  'control fill': controlFillColor(context),
};

/// The same three grounds straight off a derived scheme.
Map<String, Color> _schemeGrounds(AppColorScheme scheme) => {
  'page': scheme.background,
  'surface': scheme.surface,
  'control fill': scheme.controlFill,
};

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

  testWidgets('ink reads on every ground, for every accent', (tester) async {
    // Three grounds now carry text: the page, the raised surface and the control
    // fill. The ink roles are solved against the hardest of them, so each must
    // hold on all three — through the same accessors widgets use.
    for (final brightness in Brightness.values) {
      for (final accent in SettingsProvider.accents) {
        final context = await _contextFor(tester, accent.seed, brightness);
        final label = '${accent.name} / ${brightness.name}';
        for (final ground in _grounds(context).entries) {
          _expectContrast(
            textPrimaryColor(context),
            ground.value,
            atLeast: 12,
            what: '$label primary ink on ${ground.key}',
          );
          _expectContrast(
            textSecondaryColor(context),
            ground.value,
            atLeast: 4.5,
            what: '$label secondary ink on ${ground.key}',
          );
          _expectContrast(
            accentColor(context),
            ground.value,
            atLeast: 4.5,
            what: '$label accent ink on ${ground.key}',
          );
          _expectContrast(
            errorColor(context),
            ground.value,
            atLeast: 4.5,
            what: '$label error on ${ground.key}',
          );
          _expectContrast(
            successColor(context),
            ground.value,
            atLeast: 4.5,
            what: '$label success on ${ground.key}',
          );
        }
      }
    }
  });

  test('vivid wordmark stays readable for every accent in both modes', () {
    for (final brightness in Brightness.values) {
      for (final accent in SettingsProvider.accents) {
        final scheme = deriveColorScheme(accent.seed, brightness);
        for (final ground in [scheme.background, scheme.surface]) {
          _expectContrast(
            scheme.brandAccent,
            ground,
            atLeast: 4.5,
            what: '${accent.name} ${brightness.name} wordmark',
          );
        }
        if (brightness == Brightness.light) {
          // Light mode darkens the accent for text, which mutes it; the
          // wordmark keeps the signature chroma.
          expect(
            oklchOf(scheme.brandAccent).c,
            greaterThan(oklchOf(scheme.accent).c),
            reason:
                '${accent.name} wordmark should be more vivid than controls',
          );
        } else {
          // Dark mode's accent is the signature tone, and a separately solved
          // wordmark read as a second, brighter colour beside it.
          expect(
            scheme.brandAccent,
            scheme.accent,
            reason: '${accent.name} dark wordmark is the accent itself',
          );
          expect(
            scheme.accentFill,
            scheme.accent,
            reason: '${accent.name} dark fill is the accent itself',
          );
        }
      }
    }
  });

  testWidgets('today stays legible beside a trained bar for every accent', (
    tester,
  ) async {
    final today = DateTime(2026, 10, 1);
    for (final brightness in Brightness.values) {
      for (final accent in SettingsProvider.accents) {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: buildTheme(accent.seed, brightness),
            home: Scaffold(
              body: TrainingSnapshot(
                plans: const [],
                sessions: [
                  WorkoutSession(
                    date: today,
                    planName: 'Push',
                    exercises: const [],
                  ),
                ],
                now: today,
                onOpenWeeklyTraining: () {},
              ),
            ),
          ),
        );
        final day = find.byKey(const ValueKey('training-day-3'));
        final context = tester.element(day);
        final page = backgroundColor(context);
        final dot = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('training-day-today-dot')),
        );
        _expectContrast(
          (dot.decoration as BoxDecoration).color!,
          page,
          atLeast: 3,
          what: '${accent.name} ${brightness.name} today dot on page',
        );
        final bar = tester.widget<Container>(
          find.descendant(of: day, matching: find.byType(Container)),
        );
        expect(
          (bar.decoration! as BoxDecoration).color,
          accentFillColor(context),
        );
        final label = tester.widget<Text>(
          find.descendant(of: day, matching: find.byType(Text)),
        );
        _expectContrast(
          label.style!.color!,
          page,
          atLeast: 4.5,
          what: '${accent.name} ${brightness.name} today letter on page',
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey('weekly-training-link')))
              .height,
          greaterThanOrEqualTo(48),
        );
      }
    }
  });

  group('accent roles meet their targets', () {
    for (final brightness in Brightness.values) {
      for (final accent in SettingsProvider.accents) {
        test('${accent.name} / ${brightness.name}', () {
          final scheme = deriveColorScheme(accent.seed, brightness);

          // The text accent is solved against the hardest ground, so it has to
          // clear 4.5:1 on all three. This is the assertion light mode used to
          // fail outright: it drew the dark hexes, CYAN at 1.79:1.
          for (final ground in _schemeGrounds(scheme).entries) {
            _expectContrast(
              scheme.accent,
              ground.value,
              atLeast: 4.5,
              what: '${accent.name} accent on ${ground.key}',
            );
          }

          // A fill only needs its edge to read, but it must read on both grounds
          // too — a filled button sits on the page and inside cards.
          _expectContrast(
            scheme.accentFill,
            scheme.background,
            atLeast: 3.0,
            what: '${accent.name} accentFill on background',
          );

          // The pairing that broke on 10 of 14 legacy variants.
          _expectContrast(
            scheme.onAccent,
            scheme.accentFill,
            atLeast: 4.5,
            what: '${accent.name} onAccent on accentFill',
          );
        });
      }
    }

    testWidgets('primary buttons use the solved fill pairing', (tester) async {
      for (final brightness in Brightness.values) {
        for (final accent in SettingsProvider.accents) {
          final context = await _contextFor(tester, accent.seed, brightness);
          final scheme = Theme.of(context).extension<AppColorScheme>()!;
          final style = Theme.of(context).elevatedButtonTheme.style!;
          final background = style.backgroundColor!.resolve({})!;
          final foreground = style.foregroundColor!.resolve({})!;
          final label = '${accent.name} / ${brightness.name}';

          expect(
            background,
            scheme.accentFill,
            reason: '$label: primary ground must use accentFill',
          );
          expect(
            foreground,
            scheme.onAccent,
            reason: '$label: primary label must use onAccent',
          );
          _expectContrast(
            foreground,
            background,
            atLeast: 4.5,
            what: '$label primary label on ground',
          );
        }
      }
    });
  });

  group('header mesh', () {
    testWidgets('tones are the accent plus two analogous neighbours', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        for (final accent in SettingsProvider.accents) {
          final context = await _contextFor(tester, accent.seed, brightness);
          final tones = headerMeshTones(context);
          final label = '${accent.name} / ${brightness.name}';

          expect(
            tones,
            hasLength(3),
            reason: '$label: accent + two neighbours',
          );
          expect(
            tones.first,
            accentMutedColor(context),
            reason: '$label: mesh must use the solved accentMuted wash',
          );

          final baseChroma = oklchOf(tones.first).c;
          for (final neighbour in tones.skip(1)) {
            expect(
              neighbour.a,
              1.0,
              reason: '$label: blob tones must be opaque',
            );
            expect(
              oklchOf(neighbour).c,
              lessThanOrEqualTo(baseChroma + 0.02),
              reason: '$label: neighbour is more chromatic than the base',
            );
          }
        }
      }
    });
  });

  group('elevation reads as light', () {
    // The contract the neutrals keep. Light mode used to step its cards *down*
    // from the page, to #E3E3E3 with a 1.9:1 outline, so every sheet, dialog,
    // field and tile was a grey slab sunk into the page. A raised surface is now
    // lighter than the page in both modes; light mode makes it white and lets a
    // shadow lift it, dark mode lets the fill and a hairline do it.
    //
    // Neutral tones don't depend on the accent, but they are solved in the same
    // pass, so they are checked for every accent to catch any future coupling.
    for (final brightness in Brightness.values) {
      for (final accent in SettingsProvider.accents) {
        test('${accent.name} / ${brightness.name}', () {
          final scheme = deriveColorScheme(accent.seed, brightness);
          final isDark = brightness == Brightness.dark;
          final page = oklchOf(scheme.background).l;
          final raised = oklchOf(scheme.surface).l;
          final control = oklchOf(scheme.controlFill).l;

          expect(
            raised,
            greaterThan(page),
            reason: 'a raised surface must be lighter than the page',
          );
          if (!isDark) {
            expect(
              scheme.surface.toARGB32(),
              0xFFFFFFFF,
              reason: 'light mode raises onto white',
            );
          }

          // The lift is a perceptual step, not a ratio: near black, WCAG's
          // +0.05 term makes the same ratio cost dark mode ~2.4x the step,
          // which is how a "quiet" card once came out #2F2F2F (0.146). Big
          // enough to see, small enough that dark mode still reads as black.
          // Dark mode's range sits higher: it has no shadow, and its edge is
          // only lit along the top.
          expect(
            raised - page,
            isDark
                ? inInclusiveRange(0.05, 0.08)
                : inInclusiveRange(0.03, 0.06),
          );

          // The control fill steps away from *both* grounds, so a field or a
          // stepper reads on the page and inside a sheet: below the page in
          // light mode, above the sheet in dark mode.
          if (isDark) {
            expect(control - raised, greaterThanOrEqualTo(0.03));
          } else {
            expect(page - control, greaterThanOrEqualTo(0.02));
            expect(raised - control, greaterThanOrEqualTo(0.05));
          }
        });
      }
    }

    test(
      'dark mode lifts a little further than light, never to a grey box',
      () {
        double liftFor(Brightness brightness) {
          final scheme = deriveColorScheme(
            SettingsProvider.accents.first.seed,
            brightness,
          );
          return oklchOf(scheme.surface).l - oklchOf(scheme.background).l;
        }

        // Light mode's card also casts a shadow; dark mode's has only the fill
        // and a lit top edge, so its fill steps further. Not much further:
        // the #2F2F2F grey box was 3.5x light mode's lift.
        final dark = liftFor(Brightness.dark);
        final light = liftFor(Brightness.light);
        expect(
          dark / light,
          inInclusiveRange(1.0, 1.75),
          reason:
              'lift is ${dark.toStringAsFixed(3)} dark vs '
              '${light.toStringAsFixed(3)} light',
        );
      },
    );

    testWidgets('a raised card always has an edge as well as a fill', (
      tester,
    ) async {
      // The fill step is small on purpose, so it never separates a card on its
      // own: that was the invisible-card bug (1.10:1, no edge). Light mode
      // casts a shadow. Dark mode, where a shadow has nothing to fall on, lights
      // the top edge; a hairline drawn all round made the card an outline.
      for (final brightness in Brightness.values) {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: buildTheme(SettingsProvider.accents.first.seed, brightness),
            home: Builder(
              builder: (c) {
                context = c;
                return const RaisedCard(child: SizedBox(height: 40));
              },
            ),
          ),
        );
        final decoration = raisedDecoration(context);
        final box =
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byType(RaisedCard),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(RaisedCard),
                matching: find.byType(Material),
              )
              .first,
        );
        final side = (material.shape! as RoundedRectangleBorder).side;

        expect(raisedShadow(context), isNotEmpty);
        expect(box.boxShadow, raisedShadow(context));
        expect(decoration.boxShadow, raisedShadow(context));
        expect(side, BorderSide.none);
        expect(decoration.border, isNull);
        if (brightness == Brightness.dark) {
          // A hard edge, lifted above the card and lighter than it, so the
          // only part left showing is a lit band along the top.
          final [edge] = raisedShadow(context);
          expect(edge.blurRadius, 0);
          expect(edge.offset.dy, lessThan(0));
          expect(edge.offset.dx, 0);
          expect(
            oklchOf(edge.color).l,
            greaterThan(oklchOf(surfaceColor(context)).l),
          );
        }
        expect(material.color, surfaceColor(context));
      }
    });
  });

  group('lines', () {
    for (final brightness in Brightness.values) {
      test('hairlines separate, borders find / ${brightness.name}', () {
        final scheme = deriveColorScheme(
          SettingsProvider.accents.first.seed,
          brightness,
        );

        // A hairline separates; it must be seen, but it must never frame. The
        // old single border was solved to 3:1 and drawn round every card, tile
        // and chip, so the whole app was outlined.
        final hairline = contrastRatio(scheme.hairline, scheme.surface);
        expect(
          hairline,
          inInclusiveRange(1.2 - _quantisationSlack, 1.35),
          reason: 'hairline on surface ${hairline.toStringAsFixed(2)}:1',
        );
        _expectContrast(
          scheme.hairline,
          scheme.background,
          atLeast: 1.1,
          what: 'hairline on page',
        );

        // The border is the edge of an *unfilled* control — an unselected
        // radio, an off switch — so it holds WCAG 1.4.11's 3:1 wherever such
        // a control can sit.
        for (final ground in ['page', 'surface']) {
          _expectContrast(
            scheme.border,
            _schemeGrounds(scheme)[ground]!,
            atLeast: 3.0,
            what: 'border on $ground',
          );
        }
        expect(
          contrastRatio(scheme.border, scheme.surface),
          greaterThan(contrastRatio(scheme.hairline, scheme.surface)),
          reason: 'a hairline must stay quieter than a control edge',
        );
      });
    }

    testWidgets('filled fields ring only for focus and errors', (tester) async {
      for (final brightness in Brightness.values) {
        for (final accent in SettingsProvider.accents) {
          final context = await _contextFor(tester, accent.seed, brightness);
          final input = Theme.of(context).inputDecorationTheme;
          final label = '${accent.name} / ${brightness.name}';

          expect(input.filled, isTrue, reason: '$label field is filled');
          expect(input.fillColor, controlFillColor(context));
          expect(
            input.enabledBorder!.borderSide.style,
            BorderStyle.none,
            reason: '$label resting field draws no outline',
          );
          // The focus ring is the only thing marking focus, so it has to read
          // against the fill it surrounds (WCAG 1.4.11).
          _expectContrast(
            input.focusedBorder!.borderSide.color,
            controlFillColor(context),
            atLeast: 3.0,
            what: '$label focus ring on field',
          );
          _expectContrast(
            input.errorBorder!.borderSide.color,
            controlFillColor(context),
            atLeast: 3.0,
            what: '$label error ring on field',
          );
        }
      }
    });
  });

  group('semantic colours are legible as text and as grounds', () {
    for (final brightness in Brightness.values) {
      test('error and success / ${brightness.name}', () {
        final scheme = deriveColorScheme(
          SettingsProvider.accents.first.seed,
          brightness,
        );

        for (final entry
            in {'error': scheme.error, 'success': scheme.success}.entries) {
          // Read as text on every ground…
          for (final ground in _schemeGrounds(scheme).entries) {
            _expectContrast(
              entry.value,
              ground.value,
              atLeast: 4.5,
              what: '${entry.key} on ${ground.key}',
            );
          }
          // …and carry a label when used as a ground, which both are (a filled
          // delete button, the [PR] badge).
          _expectContrast(
            onColor(entry.value),
            entry.value,
            atLeast: 4.5,
            what: 'onColor(${entry.key}) on ${entry.key}',
          );
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
              reason:
                  '${accent.name} ${brightness.name}: heatmap step $i '
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
      testWidgets('all ${kPlanColors.length} slots / ${brightness.name}', (
        tester,
      ) async {
        final context = await _contextFor(
          tester,
          SettingsProvider.accents.first.seed,
          brightness,
        );
        for (var slot = 0; slot < kPlanColors.length; slot++) {
          final resolved = planSwatch(slot, context);
          // Plan colours label rows and cards and draw stripes on them. All ten
          // used to score 1.53–3.44 on the light background because there were
          // no light variants at all.
          for (final ground in _grounds(context).entries) {
            _expectContrast(
              resolved,
              ground.value,
              atLeast: 4.5,
              what: 'plan slot $slot on ${ground.key}',
            );
          }
          _expectContrast(
            onColor(resolved),
            resolved,
            atLeast: 4.5,
            what: 'onColor(plan slot $slot) on itself',
          );
        }
      });

      testWidgets('stored values map back to a slot / ${brightness.name}', (
        tester,
      ) async {
        final context = await _contextFor(
          tester,
          SettingsProvider.accents.first.seed,
          brightness,
        );

        // Plans persist a raw ARGB value, so a legacy hex has to land on the
        // nearest hue rather than needing a Hive migration. Every value the
        // picker can write must round-trip to the slot that wrote it, or the
        // picker stops highlighting the user's own choice.
        for (var slot = 0; slot < kPlanColors.length; slot++) {
          expect(
            planSlotOf(kPlanColors[slot]),
            slot,
            reason: 'slot $slot did not round-trip through planSlotOf',
          );
        }

        // A null plan colour means "inherit the accent", not "transparent".
        expect(planColorOf(null, context), accentColor(context));
      });
    }
  });

  group('the RPE ramp', () {
    for (final brightness in Brightness.values) {
      testWidgets('every step is legible / ${brightness.name}', (tester) async {
        final context = await _contextFor(
          tester,
          SettingsProvider.accents.first.seed,
          brightness,
        );
        // All six RPE values, not just the six distinct steps: the thresholds
        // are part of the contract.
        for (var rpe = 1; rpe <= 10; rpe++) {
          for (final ground in _grounds(context).entries) {
            _expectContrast(
              rpeColor(rpe, context),
              ground.value,
              atLeast: 4.5,
              what: 'RPE $rpe on ${ground.key}',
            );
          }
        }
      });

      testWidgets('reads as a progression of hue / ${brightness.name}', (
        tester,
      ) async {
        final context = await _contextFor(
          tester,
          SettingsProvider.accents.first.seed,
          brightness,
        );

        // The ramp's meaning is carried by hue. Distinct tones for distinct
        // bands is the minimum: six shades of pale (which is what light mode
        // used to show) conveys nothing.
        final distinct = {
          for (final rpe in [1, 3, 5, 7, 9, 10])
            rpeColor(rpe, context).toARGB32(),
        };
        expect(
          distinct.length,
          6,
          reason: 'RPE bands collapsed into ${distinct.length} colours',
        );
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
        expect(
          wrong,
          lessThan(4.5),
          reason:
              '${accent.name}: onAccent on accent scored '
              '${wrong.toStringAsFixed(2)}:1 — if this now passes, the ban '
              'below is obsolete and should be reconsidered, not deleted',
        );
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
          final window = lines
              .sublist(i, (i + 12).clamp(0, lines.length))
              .join('\n');
          if (window.contains('onAccentColor(context)')) {
            offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'These sites pair an `accent` ground with an `onAccent` '
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

      expect(
        flags(violation),
        isTrue,
        reason: 'the scan no longer detects the bug it was written for',
      );
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
    Color oldRule(Color ground) =>
        ground.computeLuminance() > 0.5
            ? const Color(0xFF000000)
            : const Color(0xFFFFFFFF);

    test('never scores worse, and fixes 10 of the 14 variants', () {
      var improved = 0;
      legacy.forEach((name, variants) {
        for (final variant in variants) {
          final now = contrastRatio(bestForeground(variant), variant);
          final before = contrastRatio(oldRule(variant), variant);
          expect(
            now,
            greaterThanOrEqualTo(before),
            reason:
                '$name ${variant.toARGB32().toRadixString(16)}: '
                'bestForeground (${now.toStringAsFixed(2)}) is worse than '
                'the old rule (${before.toStringAsFixed(2)})',
          );
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
        expect(
          contrastRatio(bestForeground(grey), grey),
          greaterThanOrEqualTo(4.5),
        );
      }
    });
  });
}
