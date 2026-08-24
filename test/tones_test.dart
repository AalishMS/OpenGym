import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/theme/tones.dart';

/// Unit tests for the colour solver.
///
/// The golden values below were produced by the comparison harness in
/// `docs/color-study.html` — the same formula in JavaScript, whose output was
/// reviewed and chosen (direction A). Asserting the hexes here, rather than only
/// the contrast properties, is what makes the Dart a *port* of the reviewed
/// design instead of a second implementation that happens to pass.
///
/// Channels are compared to ±1. The two implementations quantise float channels
/// to 8-bit independently, so a last-bit difference is round-off rather than a
/// divergence in the maths — Dart returns `2f2f2f` for a solved neutral where
/// the JS returned `2f2f2e`, and Dart is the more correct of the two.
void main() {
  // Direction A, dark.
  const bgDark = Color(0xFF0D0D0D);
  const surfaceDark = Color(0xFF2F2F2E);
  // Direction A, light.
  const bgLight = Color(0xFFF7F7F6);
  const surfaceLight = Color(0xFFE2E2E2);
  const neutralSeed = Color(0xFF8A8A8A);

  /// Compares against a golden ARGB literal, tolerating 1/255 per channel.
  ///
  /// `Color` equality cannot be used: since Flutter 3.27 a `Color` holds float
  /// components, so one built by `Color.from` never equals a `const Color(0x…)`
  /// even when both render to the same pixel.
  void expectHex(Color actual, int golden, {String? reason}) {
    final got = actual.toARGB32();
    final label = '${reason ?? ''} got 0x${got.toRadixString(16)}, '
        'want 0x${golden.toRadixString(16)}';
    for (final shift in [16, 8, 0]) {
      expect((((got >> shift) & 0xFF) - ((golden >> shift) & 0xFF)).abs(),
          lessThanOrEqualTo(1),
          reason: label);
    }
  }

  group('OKLCh conversion', () {
    test('round-trips every channel corner within 1/255', () {
      const samples = [
        Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFF808080),
        Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFF0000FF),
        Color(0xFF00A8FF), Color(0xFF8B5CF6), Color(0xFF7C8AA0),
      ];
      for (final c in samples) {
        final o = oklchOf(c);
        final back = colorFromOklch(o.l, o.c, o.h);
        // 1/255 ≈ 0.0039; allow a shade over for float round-off.
        expect((back.r - c.r).abs(), lessThan(0.005), reason: '$c red');
        expect((back.g - c.g).abs(), lessThan(0.005), reason: '$c green');
        expect((back.b - c.b).abs(), lessThan(0.005), reason: '$c blue');
      }
    });

    test('a true neutral has zero chroma', () {
      expect(oklchOf(const Color(0xFF8A8A8A)).c, lessThan(0.001));
    });

    test('lightness is ordered black → grey → white', () {
      expect(oklchOf(const Color(0xFF000000)).l, lessThan(0.01));
      expect(oklchOf(const Color(0xFFFFFFFF)).l, greaterThan(0.99));
      final mid = oklchOf(const Color(0xFF808080)).l;
      expect(mid, greaterThan(0.4));
      expect(mid, lessThan(0.7));
    });
  });

  group('contrastRatio', () {
    test('spans 1:1 to 21:1', () {
      expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
          closeTo(21.0, 0.01));
      expect(contrastRatio(const Color(0xFF7C8AA0), const Color(0xFF7C8AA0)),
          closeTo(1.0, 0.0001));
    });

    test('is symmetric', () {
      expect(contrastRatio(bgDark, surfaceDark),
          closeTo(contrastRatio(surfaceDark, bgDark), 1e-9));
    });
  });

  group('bestForeground', () {
    /// Every accent variant the app shipped before this change: 7 accents × the
    /// hand-picked dark/light pair.
    const legacyVariants = [
      Color(0xFF00A8FF), Color(0xFF0077CC), // electric blue
      Color(0xFFFF9500), Color(0xFFCC7700), // warm amber
      Color(0xFFFF5722), Color(0xFFE64A19), // deep orange
      Color(0xFFFF1493), Color(0xFFCC1177), // hot pink
      Color(0xFF00CED1), Color(0xFF00A5A8), // cyan
      Color(0xFF8B5CF6), Color(0xFF6D28D9), // purple
      Color(0xFFA0A0A0), Color(0xFF666666), // steel gray
    ];

    /// What `onColor` used to do: flip at luminance 0.5.
    Color oldRule(Color ground) => ground.computeLuminance() > 0.5
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);

    test('never picks the worse of black and white', () {
      for (final v in legacyVariants) {
        expect(contrastRatio(bestForeground(v), v),
            greaterThanOrEqualTo(contrastRatio(oldRule(v), v) - 1e-9),
            reason: '$v');
      }
    });

    test('clears AA on any possible ground', () {
      // Provable, not incidental: the crossover luminance is 0.179, where both
      // candidates score (0.179 + 0.05) / 0.05 = 4.58. No ground can do worse
      // than that, so the better candidate always clears 4.5.
      for (var i = 0; i <= 255; i++) {
        final g = Color.fromARGB(255, i, i, i);
        expect(contrastRatio(bestForeground(g), g), greaterThanOrEqualTo(4.5),
            reason: 'grey $i');
      }
      for (final v in legacyVariants) {
        expect(contrastRatio(bestForeground(v), v), greaterThanOrEqualTo(4.5),
            reason: '$v');
      }
    });

    test('the old rule did fail AA — this is the bug being fixed', () {
      final failures =
          legacyVariants.where((v) => contrastRatio(oldRule(v), v) < 4.5);
      expect(failures, isNotEmpty,
          reason: 'if this passes, the premise of the fix is wrong');

      // CYAN was the worst: white on #00CED1 is 1.95:1, black is 10.75:1.
      const cyan = Color(0xFF00CED1);
      expect(contrastRatio(oldRule(cyan), cyan), closeTo(1.95, 0.02));
      expect(contrastRatio(bestForeground(cyan), cyan), closeTo(10.75, 0.02));
    });
  });

  group('solveForContrast', () {
    test('reproduces the reviewed neutral ramp (direction A)', () {
      Color solved(Color against, double target, bool lighter) =>
          solveForContrast(
            seed: neutralSeed,
            against: against,
            target: target,
            preferLighter: lighter,
          );

      // dark
      expectHex(solved(bgDark, 1.45, true), 0xFF2F2F2E, reason: 'surface dark');
      expectHex(solved(surfaceDark, 3.00, true), 0xFF787878,
          reason: 'border dark');
      expectHex(solved(bgDark, 13.0, true), 0xFFD4D4D4,
          reason: 'textPrimary dark');
      expectHex(solved(surfaceDark, 4.5, true), 0xFF969696,
          reason: 'textSecondary dark');
      // light
      expectHex(solved(bgLight, 1.20, false), 0xFFE2E2E2,
          reason: 'surface light');
      expectHex(solved(surfaceLight, 1.90, false), 0xFFA5A5A5,
          reason: 'border light');
      expectHex(solved(bgLight, 13.0, false), 0xFF2C2C2C,
          reason: 'textPrimary light');
      expectHex(solved(surfaceLight, 4.5, false), 0xFF646464,
          reason: 'textSecondary light');
    });

    test('reproduces the reviewed accent tones (direction A)', () {
      // Purple is too dark on a dark card (4.11:1) and gets lifted.
      expectHex(
        solveForContrast(
          seed: const Color(0xFF8B5CF6),
          against: surfaceDark,
          target: 4.5,
          preferLighter: true,
          anchor: ToneAnchor.seed,
        ),
        0xFFA97DFF,
        reason: 'purple dark',
      );
      // Cyan is unusable in light mode as shipped (1.79:1) and gets darkened.
      expectHex(
        solveForContrast(
          seed: const Color(0xFF00CED1),
          against: surfaceLight,
          target: 4.5,
          preferLighter: false,
          anchor: ToneAnchor.seed,
        ),
        0xFF007075,
        reason: 'cyan light',
      );
      // Steel gray, the accent that must stay quiet but not vanish.
      expectHex(
        solveForContrast(
          seed: const Color(0xFF7C8AA0),
          against: surfaceDark,
          target: 4.5,
          preferLighter: true,
          anchor: ToneAnchor.seed,
        ),
        0xFF8897AD,
        reason: 'steel dark',
      );
    });

    test('ToneAnchor.seed keeps a seed that already passes', () {
      const cyan = Color(0xFF00CED1);
      expect(contrastRatio(cyan, surfaceDark), greaterThan(4.5));
      expect(
        solveForContrast(
          seed: cyan,
          against: surfaceDark,
          target: 4.5,
          preferLighter: true,
          anchor: ToneAnchor.seed,
        ),
        cyan,
        reason: 'a passing foreground seed is the intended colour',
      );
    });

    test('ToneAnchor.ground lands at the target, not merely past it', () {
      // The bug this enum exists to prevent: a mid-grey seed already clears a
      // 1.45:1 surface target, so anchoring to the seed would hand back
      // mid-grey cards.
      expect(contrastRatio(neutralSeed, bgDark), greaterThan(1.45));
      final surface = solveForContrast(
        seed: neutralSeed,
        against: bgDark,
        target: 1.45,
        preferLighter: true,
      );
      expect(surface, isNot(neutralSeed));
      expect(contrastRatio(surface, bgDark), closeTo(1.45, 0.02));
    });

    test('meets its target for every accent seed, both modes, on both grounds',
        () {
      const seeds = [
        Color(0xFF00A8FF), Color(0xFFFF9500), Color(0xFFFF5722),
        Color(0xFFFF1493), Color(0xFF00CED1), Color(0xFF8B5CF6),
        Color(0xFF7C8AA0), Color(0xFF22C55E),
      ];
      for (final seed in seeds) {
        for (final (bg, surface, lighter) in [
          (bgDark, surfaceDark, true),
          (bgLight, surfaceLight, false),
        ]) {
          // Solved against whichever ground is harder, so both must pass.
          final worse = contrastRatio(seed, bg) < contrastRatio(seed, surface)
              ? bg
              : surface;
          final accent = solveForContrast(
            seed: seed,
            against: worse,
            target: 4.5,
            preferLighter: lighter,
            anchor: ToneAnchor.seed,
          );
          expect(contrastRatio(accent, bg), greaterThanOrEqualTo(4.48),
              reason: '$seed accent on background');
          expect(contrastRatio(accent, surface), greaterThanOrEqualTo(4.48),
              reason: '$seed accent on surface');
        }
      }
    });

    test('preserves hue and chroma when the result stays in gamut', () {
      const seed = Color(0xFF7C8AA0); // low chroma, no clamping en route
      final before = oklchOf(seed);
      final after = oklchOf(solveForContrast(
        seed: seed,
        against: surfaceDark,
        target: 6.0,
        preferLighter: true,
      ));
      expect(after.c, closeTo(before.c, 0.005));
      expect(after.h, closeTo(before.h, 0.02));
    });

    test('returns the in-gamut extreme when the target is unreachable', () {
      // Nothing sharing pure yellow's hue and chroma reaches 21:1 on white.
      const seed = Color(0xFFFFFF00);
      const white = Color(0xFFFFFFFF);
      final solved = solveForContrast(
        seed: seed,
        against: white,
        target: 21.0,
        preferLighter: false,
      );

      final s = oklchOf(seed);
      final extreme = colorFromOklch(0.0, s.c, s.h);
      expect(solved.toARGB32(), extreme.toARGB32(),
          reason: 'must hand back the darkest tone of this hue, not give up');
      expect(contrastRatio(solved, white), lessThan(21.0),
          reason: 'if this passes, the target was reachable after all');
      expect(contrastRatio(solved, white), greaterThan(19.0),
          reason: 'best effort, not a shrug');

      // And note what "extreme" means: L = 0 at this chroma is outside sRGB, so
      // the clamp lands on a very dark yellow-green rather than on black. The
      // solver reports the colour a screen can show, which is why contrast is
      // measured after clamping.
      expect(oklchOf(solved).l, greaterThan(0.1));
      expect(oklchOf(solved).l, lessThan(0.2));
    });
  });

  group('toneBetween', () {
    /// The three realized step sizes of the heatmap ramp for [seed].
    List<double> rampSteps(Color seed) {
      final l = [1 / 3, 2 / 3, 1.0]
          .map((f) =>
              oklchOf(toneBetween(seed: seed, from: bgDark, to: seed, fraction: f))
                  .l)
          .toList();
      return [l[1] - l[0], l[2] - l[1]];
    }

    const purple = Color(0xFF8B5CF6);

    test('gives perceptually even steps for every accent', () {
      // Purple is excluded and pinned in its own test below — it is the one
      // accent whose ramp leaves sRGB.
      const seeds = [
        Color(0xFF00A8FF), Color(0xFFFF9500), Color(0xFF00CED1),
        Color(0xFF7C8AA0), Color(0xFF22C55E),
      ];
      for (final seed in seeds) {
        final steps = rampSteps(seed);
        // Tight on purpose. Measured drift for these five is ≤0.004, so a loose
        // tolerance here would let one of them regress unnoticed.
        expect(steps[0], closeTo(steps[1], 0.005), reason: '$seed step sizes');
        expect(steps[0], greaterThan(0), reason: '$seed must ascend');
      }
    });

    test('ascends without a cliff even where sRGB clamps the ramp', () {
      // Purple carries the highest chroma in the set, and its darkest step sits
      // outside sRGB: the clamp pushes that tone lighter than asked, which
      // squeezes the first step to 0.119 against the second's 0.149.
      //
      // Left as-is deliberately. Trimming purple's chroma to make the arithmetic
      // tidy would be a change to the palette, which is out of scope here, and
      // the visible cost is one heatmap cell a shade light. What must hold is
      // that the ramp still ascends and has no cliff — that was the actual bug
      // in the alpha ramp this replaces.
      final steps = rampSteps(purple);
      expect(steps[0], greaterThan(0));
      expect(steps[1], greaterThan(0));
      expect(steps[0] / steps[1], greaterThan(0.7), reason: 'no cliff');
      expect(steps[0], closeTo(0.1186, 0.001), reason: 'known compression');
      expect(steps[1], closeTo(0.1489, 0.001));
    });

    test('fraction 0 and 1 land on the endpoints', () {
      // A low-chroma seed, so the whole ramp stays inside sRGB and the endpoints
      // are exact. See the evenness test for what clamping does to a saturated
      // one.
      const seed = Color(0xFF7C8AA0);
      expect(
        oklchOf(toneBetween(seed: seed, from: bgDark, to: seed, fraction: 0.0))
            .l,
        closeTo(oklchOf(bgDark).l, 0.001),
      );
      expect(
        oklchOf(toneBetween(seed: seed, from: bgDark, to: seed, fraction: 1.0))
            .l,
        closeTo(oklchOf(seed).l, 0.001),
      );
    });
  });
}
