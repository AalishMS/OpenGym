import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/workout_session.dart';
import '../providers/settings_provider.dart';
import '../services/exercise_catalog.dart';
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
/// The open summary is exactly what Share sends. Figures show their final
/// values from the first frame, including when shared immediately. Records
/// come from the same check Finish has always made (heaviest weight per
/// exercise); a first-time exercise is counted separately from records.
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
  final _summaryKey = GlobalKey();
  final _shareKey = GlobalKey();
  bool _sharing = false;

  List<WorkoutSession> get _history =>
      widget.history ??
      HiveService.getCompletedSessions(splitId: widget.session.splitId);

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      // Finish any pending layout/paint before reading the boundary. The
      // figures themselves are final immediately; no animation enters the PNG.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _summaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final shareBox =
          _shareKey.currentContext!.findRenderObject()! as RenderBox;
      final origin = shareBox.localToGlobal(Offset.zero) & shareBox.size;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await _encodePng(image);
      if (!mounted) return;
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
        sharePositionOrigin: origin,
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

  Future<ByteData?> _encodePng(ui.Image image) async {
    try {
      return await image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = context.watch<SettingsProvider?>()?.weightUnit ?? 'kg';
    final session = widget.session;
    final history = _history;
    const analytics = StatisticsAnalyticsService();
    final stats = analytics.sessionStatistics(session);
    final previous = history
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
        previous == null
            ? null
            : analytics.sessionStatistics(previous).volumeLoad;
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

    // Zero added weight can be a performed bodyweight exercise. First logs
    // depend on exercise identity and performed sets, not a positive weight PR.
    final previousExercises = {
      for (final other in history)
        if (other.id != session.id &&
            other.deletedAt == null &&
            other.isCompleted &&
            other.splitId == session.splitId)
          for (final exercise in other.exercises)
            if (exercise.sets.any((set) => set.reps > 0))
              ExerciseCatalog.identity(exercise.name, exercise.exerciseId),
    };
    final loggedExercises = {
      for (final exercise in session.exercises)
        if (exercise.sets.any((set) => set.reps > 0))
          ExerciseCatalog.identity(exercise.name, exercise.exerciseId),
    };
    final realRecords = [
      for (final record in widget.records)
        if (previousExercises.contains(
          ExerciseCatalog.identity(record.exerciseName, record.exerciseId),
        ))
          record,
    ];
    final firstLogs = loggedExercises.difference(previousExercises).length;

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppHeader(
        leading: AppBackButton(onPressed: () => Navigator.pop(context)),
        title: const Text('Workout logged'),
        actions: [
          IconButton(
            key: _shareKey,
            tooltip: 'Share workout',
            onPressed: _sharing ? null : _share,
            icon:
                _sharing
                    ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accentColor(context),
                      ),
                    )
                    : const Icon(
                      LucideIcons.share2,
                      key: ValueKey('summary-share'),
                      size: 20,
                    ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: RepaintBoundary(
                key: _summaryKey,
                child: ColoredBox(
                  // The same opaque page ground travels with the PNG.
                  color: backgroundColor(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                    ),
                    child: _SummaryContent(
                      session: session,
                      volumeLoad: stats.volumeLoad,
                      totalSets: stats.totalSets,
                      totalReps: stats.totalReps,
                      previousVolume: previousVolume,
                      workoutOfWeek: thisWeek,
                      records: realRecords,
                      firstLogs: firstLogs,
                      unit: unit,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('summary-done'),
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: accentFillColor(context),
                    foregroundColor: onAccentColor(context),
                    minimumSize: const Size.fromHeight(52),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.button,
                    ),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A training result on the page ground: the workout leads, volume carries
/// the emphasis, and supporting figures and records stay open and readable.
class _SummaryContent extends StatelessWidget {
  final WorkoutSession session;
  final double volumeLoad;
  final int totalSets;
  final int totalReps;
  final double? previousVolume;
  final int workoutOfWeek;
  final List<PRResult> records;
  final int firstLogs;
  final String unit;

  const _SummaryContent({
    required this.session,
    required this.volumeLoad,
    required this.totalSets,
    required this.totalReps,
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
    final metrics = <(String, String)>[
      if (duration != null) ('Duration', formatStatisticsDuration(duration)),
      ('Sets', '$totalSets'),
      ('Reps', '$totalReps'),
    ];
    final volume = formatVolumeLoad(volumeLoad, unit);
    final unitAt = volume.lastIndexOf(' ');
    return Column(
      key: const ValueKey('workout-summary-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              formatStatisticsDate(session.date),
              style: textTheme.bodySmall,
            ),
            Text(
              'Workout $workoutOfWeek this week',
              style: textTheme.bodySmall?.copyWith(color: accentColor(context)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            session.planName,
            style: textTheme.displaySmall?.copyWith(
              fontSize: 30,
              height: 1.12,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          workoutContext(session),
          style: textTheme.bodyMedium?.copyWith(color: secondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Volume lifted',
          style: textTheme.bodyMedium?.copyWith(color: secondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          label: 'Volume: $volume',
          excludeSemantics: true,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: volume.substring(0, unitAt)),
                TextSpan(
                  text: volume.substring(unitAt),
                  style: AppTypography.figures(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: secondary,
                  ),
                ),
              ],
            ),
            style: AppTypography.figures(
              fontSize: 52,
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: -2,
              color: textPrimaryColor(context),
            ),
          ),
        ),
        if (change != null) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                formatSignedChange(change, (v) => '${v.round()}%'),
                style: AppTypography.figures(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color:
                      change > 0
                          ? accentColor(context)
                          : textPrimaryColor(context),
                ),
              ),
              Text('volume vs previous workout', style: textTheme.bodySmall),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Divider(height: 1, color: borderColor(context)),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            // Measure the actual type so ordinary phone scaling retains
            // columns and long durations or accessibility text wrap naturally.
            var minimumWidth = 0.0;
            for (final (label, value) in metrics) {
              for (final (text, style) in [
                (label, textTheme.bodySmall!),
                (value, _SummaryMetric.valueStyle(context)),
              ]) {
                final painter = TextPainter(
                  text: TextSpan(text: text, style: style),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                )..layout();
                if (painter.width > minimumWidth) minimumWidth = painter.width;
                painter.dispose();
              }
            }
            final columns = ((constraints.maxWidth + AppSpacing.lg) /
                    (minimumWidth + AppSpacing.lg))
                .floor()
                .clamp(1, metrics.length);
            final width =
                (constraints.maxWidth - AppSpacing.lg * (columns - 1)) /
                columns;
            return Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xl,
              children: [
                for (final (label, value) in metrics)
                  SizedBox(
                    width: width,
                    child: _SummaryMetric(label: label, value: value),
                  ),
              ],
            );
          },
        ),
        if (records.isNotEmpty || firstLogs > 0) ...[
          const SizedBox(height: AppSpacing.lg),
          Divider(height: 1, color: borderColor(context)),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (records.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.trophy, size: 20, color: accentColor(context)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  records.length == 1
                      ? 'Personal record'
                      : '${records.length} personal records',
                  style: textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final record in records) _RecordRow(record: record, unit: unit),
        ],
        if (firstLogs > 0) ...[
          Text(
            firstLogs == 1
                ? '1 exercise logged for the first time'
                : '$firstLogs exercises logged for the first time',
            style: textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const AppWordmark(fontSize: 14),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryMetric({required this.label, required this.value});

  static TextStyle valueStyle(BuildContext context) => AppTypography.figures(
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: textPrimaryColor(context),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        Text(value, style: valueStyle(context)),
      ],
    ),
  );
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
          '${record.exerciseName}: $value for ${record.reps} ${record.reps == 1 ? 'rep' : 'reps'}, was $was',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.exerciseName,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '$value × ${record.reps}',
                  style: AppTypography.figures(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: accentColor(context),
                  ),
                ),
                Text('was $was', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
