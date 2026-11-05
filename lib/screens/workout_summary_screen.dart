import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/workout_session.dart';
import '../providers/settings_provider.dart';
import '../services/hive_service.dart';
import '../services/pr_tracking_service.dart';
import '../services/statistics_analytics_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../utils/format.dart';
import '../utils/statistics_format.dart';
import '../utils/workout_context.dart';
import '../widgets/app_header.dart';
import '../widgets/app_wordmark.dart';

/// What a logged workout added up to: the moment after Finish.
///
/// The card at the top is exactly what Share sends, so what the lifter sees
/// is what their friends get. Records come from the same check Finish has
/// always made (heaviest weight per exercise); an exercise logged for the
/// first time is counted separately rather than celebrated as a record.
class WorkoutSummaryScreen extends StatefulWidget {
  final WorkoutSession session;
  final List<PRResult> records;

  /// For tests; defaults to the account's completed sessions in this split.
  final List<WorkoutSession>? history;
  final DateTime? now;

  const WorkoutSummaryScreen({
    super.key,
    required this.session,
    required this.records,
    this.history,
    this.now,
  });

  static Route<void> route({
    required WorkoutSession session,
    required List<PRResult> records,
  }) => MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => WorkoutSummaryScreen(session: session, records: records),
  );

  @override
  State<WorkoutSummaryScreen> createState() => _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends State<WorkoutSummaryScreen> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  List<WorkoutSession> get _history =>
      widget.history ??
      HiveService.getCompletedSessions(splitId: widget.session.splitId);

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary =
          _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) throw StateError('No image data');
      await Share.shareXFiles(
        [
          XFile.fromData(
            png.buffer.asUint8List(),
            mimeType: 'image/png',
            name: 'opengym-workout.png',
          ),
        ],
        fileNameOverrides: const ['opengym-workout.png'],
      );
    } catch (error) {
      debugPrint('Could not share workout summary: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not share this workout. Try again.',
            style: TextStyle(color: onColor(errorColor(context))),
          ),
          backgroundColor: errorColor(context),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = context.watch<SettingsProvider?>()?.weightUnit ?? 'kg';
    final session = widget.session;
    final history = _history;
    const analytics = StatisticsAnalyticsService();
    final stats = analytics.sessionStatistics(session);
    final previous =
        history
            .where(
              (other) =>
                  other.id != session.id &&
                  other.deletedAt == null &&
                  other.isCompleted &&
                  other.planId != null &&
                  other.planId == session.planId &&
                  other.date.isBefore(session.date),
            )
            .fold<WorkoutSession?>(
              null,
              (latest, other) =>
                  latest == null || other.date.isAfter(latest.date)
                      ? other
                      : latest,
            );
    final previousVolume =
        previous == null ? null : analytics.sessionStatistics(previous).volumeLoad;
    final weekStart = startOfWeek(session.date);
    final weekEnd = weekStart.add(const Duration(days: 7));
    final thisWeek =
        history
            .where(
              (other) =>
                  other.id != session.id &&
                  other.deletedAt == null &&
                  other.isCompleted &&
                  !other.date.isBefore(weekStart) &&
                  other.date.isBefore(weekEnd),
            )
            .length +
        1;

    final realRecords = [
      for (final record in widget.records)
        if (record.previousPR > 0) record,
    ];
    final firstLogs = widget.records.length - realRecords.length;

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppHeader(
        leading: AppBackButton(onPressed: () => Navigator.pop(context)),
        title: const Text('Workout logged'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.xl,
              ),
              children: [
                RepaintBoundary(
                  key: _cardKey,
                  // The page ground travels with the image, so a shared
                  // card never lands with transparent corners.
                  child: ColoredBox(
                    color: backgroundColor(context),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: _SummaryCard(
                        session: session,
                        volumeLoad: stats.volumeLoad,
                        totalSets: stats.totalSets,
                        previousVolume: previousVolume,
                        workoutOfWeek: thisWeek,
                        records: realRecords,
                        firstLogs: firstLogs,
                        unit: unit,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('summary-share'),
                  onPressed: _sharing ? null : _share,
                  icon: const Icon(LucideIcons.share2, size: 18),
                  label: const Text('Share'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('summary-done'),
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: accentFillColor(context),
                    foregroundColor: onAccentColor(context),
                    minimumSize: const Size.fromHeight(48),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.button,
                    ),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final WorkoutSession session;
  final double volumeLoad;
  final int totalSets;
  final double? previousVolume;
  final int workoutOfWeek;
  final List<PRResult> records;
  final int firstLogs;
  final String unit;

  const _SummaryCard({
    required this.session,
    required this.volumeLoad,
    required this.totalSets,
    required this.previousVolume,
    required this.workoutOfWeek,
    required this.records,
    required this.firstLogs,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    final duration = knownDurationSeconds(session.durationSeconds);
    final change =
        previousVolume == null || previousVolume! <= 0 || totalSets == 0
            ? null
            : (volumeLoad - previousVolume!) / previousVolume! * 100;
    return DecoratedBox(
      key: const ValueKey('workout-summary-card'),
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: AppWordmark(fontSize: 16)),
                Text(
                  formatStatisticsDate(session.date),
                  style: textTheme.labelMedium?.copyWith(color: secondary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Semantics(
              header: true,
              child: Text(session.planName, style: textTheme.displaySmall),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${workoutContext(session)} · Workout $workoutOfWeek this week',
              style: textTheme.labelMedium?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.lg,
              children: [
                if (duration != null)
                  _CountUpFigure(
                    label: 'Duration',
                    value: duration.toDouble(),
                    format: (v) => formatStatisticsDuration(v.round()),
                  ),
                _CountUpFigure(
                  label: 'Volume',
                  value: volumeLoad,
                  format: (v) => formatVolumeLoad(v, unit),
                ),
                _CountUpFigure(
                  label: 'Sets',
                  value: totalSets.toDouble(),
                  format: (v) => '${v.round()}',
                ),
              ],
            ),
            if (change != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Icon(
                    change >= 0
                        ? LucideIcons.trendingUp
                        : LucideIcons.trendingDown,
                    size: 16,
                    color: change >= 0 ? accentColor(context) : secondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${formatSignedChange(change, (v) => '${v.round()}%')} '
                      'volume vs last ${session.planName}',
                      style: AppTypography.figures(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color:
                            change >= 0
                                ? accentColor(context)
                                : textPrimaryColor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (records.isNotEmpty || firstLogs > 0) ...[
              const SizedBox(height: AppSpacing.lg),
              Divider(height: 1, thickness: 1, color: borderColor(context)),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (records.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    LucideIcons.trophy,
                    size: 16,
                    color: accentColor(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    records.length == 1
                        ? 'Personal record'
                        : '${records.length} personal records',
                    style: textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final record in records)
                _RecordRow(record: record, unit: unit),
            ],
            if (firstLogs > 0)
              Padding(
                padding: EdgeInsets.only(
                  top: records.isEmpty ? 0 : AppSpacing.sm,
                ),
                child: Text(
                  firstLogs == 1
                      ? '1 exercise logged for the first time'
                      : '$firstLogs exercises logged for the first time',
                  style: textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  final PRResult record;
  final String unit;

  const _RecordRow({required this.record, required this.unit});

  @override
  Widget build(BuildContext context) {
    final value = formatAnalyticsWeight(record.newPR, unit);
    final was = formatAnalyticsWeight(record.previousPR, unit);
    return Semantics(
      label:
          '${record.exerciseName}: $value for ${record.reps} '
          '${record.reps == 1 ? 'rep' : 'reps'}, was $was',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                record.exerciseName,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$value × ${record.reps}',
                  style: AppTypography.figures(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textPrimaryColor(context),
                  ),
                ),
                Text(
                  'was $was',
                  style: AppTypography.figures(
                    fontSize: 12,
                    color: textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A large figure that counts up once when the summary opens.
class _CountUpFigure extends StatelessWidget {
  final String label;
  final double value;
  final String Function(double) format;

  const _CountUpFigure({
    required this.label,
    required this.value,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: '$label: ${format(value)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: reduceMotion ? value : 0, end: value),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder:
                (context, shown, _) => Text(
                  format(shown),
                  style: AppTypography.figures(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: textPrimaryColor(context),
                  ),
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
