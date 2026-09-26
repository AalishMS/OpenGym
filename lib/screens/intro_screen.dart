import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/app_wordmark.dart';

/// A short, optional introduction shown once on a new installation.
class IntroScreen extends StatefulWidget {
  final Future<void> Function() onFinish;

  const IntroScreen({required this.onFinish, super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final PageController _controller = PageController();
  int _page = 0;
  bool _finishing = false;

  static const _pages = [
    (
      title: 'Make a plan that fits you',
      body:
          'Choose a ready-made split or build a plan with your own exercises.',
      label: 'Your plan',
    ),
    (
      title: 'Log as you lift',
      body:
          'Record sets, reps, and weight. Swipe between weeks and drag exercises into order as you train.',
      label: 'Today\'s workout',
    ),
    (
      title: 'See how far you\'ve come',
      body:
          'Find past sessions, personal records, and training trends in one place.',
      label: 'Your progress',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await widget.onFinish();
    } catch (error) {
      if (!mounted) return;
      setState(() => _finishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your choice. Try again.')),
      );
    }
  }

  void _next() {
    if (_page == _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: backgroundColor(context),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    0,
                  ),
                  child: Row(
                    children: [
                      const Expanded(child: AppWordmark(fontSize: 19)),
                      TextButton(
                        onPressed: _finishing ? null : _finish,
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (page) => setState(() => _page = page),
                    itemBuilder: (context, index) {
                      final page = _pages[index];
                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical: AppSpacing.xl,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedScale(
                              scale: _page == index ? 1 : .96,
                              duration:
                                  reduceMotion
                                      ? Duration.zero
                                      : const Duration(milliseconds: 420),
                              curve: Curves.easeOutCubic,
                              child: _TrainingPreview(step: index),
                            ),
                            const SizedBox(height: AppSpacing.xxl),
                            Text(
                              page.label,
                              style: AppTypography.trainingData(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.3,
                                color: accentColor(context),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(page.title, style: textTheme.displayMedium),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              page.body,
                              style: textTheme.bodyLarge?.copyWith(
                                color: textSecondaryColor(context),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.sm,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_pages.length, (index) {
                          return AnimatedContainer(
                            duration:
                                reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            width: index == _page ? 24 : 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color:
                                  index == _page
                                      ? accentColor(context)
                                      : borderColor(context),
                              borderRadius: AppRadius.chip,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _finishing ? null : _next,
                          child: Text(
                            _page == _pages.length - 1 ? 'Get started' : 'Next',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrainingPreview extends StatelessWidget {
  final int step;

  const _TrainingPreview({required this.step});

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final secondary = textSecondaryColor(context);
    final primary = textPrimaryColor(context);
    final theme = Theme.of(context).textTheme;
    final rows = switch (step) {
      0 => [
        ('Bench press', '3 sets'),
        ('Squat', '3 sets'),
        ('Pull-up', '3 sets'),
      ],
      1 => [
        ('Set 1', '8 × 60 kg'),
        ('Set 2', '8 × 60 kg'),
        ('Set 3', 'Next set'),
      ],
      _ => [
        ('Workouts', '12'),
        ('Best bench', '80 kg'),
        ('This week', '3 days'),
      ],
    };
    return Container(
      height: 278,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 32,
                decoration: BoxDecoration(
                  color: accentFillColor(context),
                  borderRadius: AppRadius.micro,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(switch (step) {
                  0 => 'Strength day',
                  1 => 'Bench press',
                  _ => 'Training summary',
                }, style: theme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Row(
                children: [
                  Icon(
                    step == 1 ? Icons.check_circle_outline : Icons.circle,
                    size: step == 1 ? 20 : 8,
                    color: accent,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      row.$1,
                      style: theme.bodyMedium?.copyWith(color: primary),
                    ),
                  ),
                  Text(
                    row.$2,
                    style: AppTypography.trainingData(
                      fontSize: 12,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: AppRadius.micro,
            child: LinearProgressIndicator(
              value: switch (step) {
                0 => .34,
                1 => .66,
                _ => .83,
              },
              minHeight: 4,
              backgroundColor: accentMutedColor(context),
              valueColor: AlwaysStoppedAnimation<Color>(
                accentFillColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
