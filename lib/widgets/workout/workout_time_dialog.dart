import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/statistics_format.dart';
import '../app_button.dart';

/// When a logged workout started and how long it took.
typedef WorkoutTime = ({DateTime start, int durationSeconds});

/// Lets a logged workout's start and duration be corrected. Returns null when
/// cancelled or nothing changed. Fields left as they were keep their exact
/// stored value, so opening and saving never rounds off seconds.
Future<WorkoutTime?> showWorkoutTimeDialog(
  BuildContext context, {
  required DateTime start,
  required int durationSeconds,
  DateTime? now,
}) => showDialog<WorkoutTime>(
  context: context,
  builder:
      (_) => _WorkoutTimeDialog(
        start: start,
        durationSeconds: durationSeconds,
        now: now,
      ),
);

class _WorkoutTimeDialog extends StatefulWidget {
  final DateTime start;
  final int durationSeconds;
  final DateTime? now;

  const _WorkoutTimeDialog({
    required this.start,
    required this.durationSeconds,
    this.now,
  });

  @override
  State<_WorkoutTimeDialog> createState() => _WorkoutTimeDialogState();
}

class _WorkoutTimeDialogState extends State<_WorkoutTimeDialog> {
  late DateTime _start = widget.start;
  late final int _initialHours = widget.durationSeconds ~/ 3600;
  late final int _initialMinutes = widget.durationSeconds % 3600 ~/ 60;
  late final TextEditingController _hours = TextEditingController(
    text: '$_initialHours',
  );
  late final TextEditingController _minutes = TextEditingController(
    text: '$_initialMinutes',
  );
  String? _error;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = _now;
    final picked = await showDatePicker(
      context: context,
      initialDate: _start.isAfter(now) ? now : _start,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _start = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _start.hour,
        _start.minute,
        _start.second,
      );
      _error = null;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _start = DateTime(
        _start.year,
        _start.month,
        _start.day,
        picked.hour,
        picked.minute,
      );
      _error = null;
    });
  }

  void _save() {
    final hours = int.tryParse(_hours.text.trim()) ?? 0;
    final minutes = int.tryParse(_minutes.text.trim()) ?? 0;
    final total = hours * 60 + minutes;
    final String? error =
        _start.isAfter(_now)
            ? "A workout can't start in the future."
            : total < 1
            ? 'Enter a duration of at least 1 minute.'
            : total >= 24 * 60
            ? 'Enter a duration under 24 hours.'
            : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final durationUnchanged =
        hours == _initialHours && minutes == _initialMinutes;
    final duration = durationUnchanged ? widget.durationSeconds : total * 60;
    if (_start == widget.start && duration == widget.durationSeconds) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop<WorkoutTime>(context, (
      start: _start,
      durationSeconds: duration,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(_start),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final label = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: textSecondaryColor(context));
    InputDecoration field(String text) => InputDecoration(
      labelText: text,
      border: const OutlineInputBorder(borderRadius: AppRadius.field),
    );
    return AlertDialog(
      title: const Text('Date and duration'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Started', style: label),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('workout-date'),
                  onPressed: _pickDate,
                  icon: const Icon(LucideIcons.calendar, size: 18),
                  label: Text(formatStatisticsDate(_start)),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('workout-start-time'),
                  onPressed: _pickTime,
                  icon: const Icon(LucideIcons.clock, size: 18),
                  label: Text(time),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Duration', style: label),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('workout-duration-hours'),
                    controller: _hours,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: field('Hours'),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    key: const ValueKey('workout-duration-minutes'),
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: field('Minutes'),
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const ValueKey('workout-time-error'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: errorColor(context)),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppButton.text(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        AppButton.primary(label: 'Save', onPressed: _save),
      ],
    );
  }
}
