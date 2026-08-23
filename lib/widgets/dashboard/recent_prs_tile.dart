import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/workout_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';

/// One exercise's personal record and the day it was first set.
class PrEntry {
  final String exercise;
  final double weight;
  final DateTime date;

  const PrEntry({
    required this.exercise,
    required this.weight,
    required this.date,
  });

  /// Best weight per exercise, newest PR first.
  ///
  /// Walks sessions oldest → newest so [date] is the day the record was *first*
  /// reached, not the last day it was matched. Exercise names are matched
  /// case-insensitively (as elsewhere in the app) but displayed as first seen.
  static List<PrEntry> fromSessions(List<WorkoutSession> sessions) {
    final best = <String, double>{};
    final when = <String, DateTime>{};
    final display = <String, String>{};

    for (final session in sessions.reversed) {
      for (final exercise in session.exercises) {
        final key = exercise.name.toLowerCase();
        display.putIfAbsent(key, () => exercise.name);
        for (final set in exercise.sets) {
          if (set.weight > (best[key] ?? 0)) {
            best[key] = set.weight;
            when[key] = session.date;
          }
        }
      }
    }

    return best.entries
        .where((e) => e.value > 0)
        .map((e) => PrEntry(
              exercise: display[e.key] ?? e.key,
              weight: e.value,
              date: when[e.key]!,
            ))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }
}

/// Newest-first feed of personal records.
class RecentPrsTile extends StatelessWidget {
  final List<PrEntry> entries;
  final int limit;

  const RecentPrsTile({required this.entries, this.limit = 8, super.key});

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);
    final shown = entries.take(limit).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    e.exercise.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: textPrimary,
                      letterSpacing: 0.02,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${formatWeight(e.weight)}KG',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 56,
                  child: Text(
                    formatRelativeDay(e.date),
                    textAlign: TextAlign.right,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      color: textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
