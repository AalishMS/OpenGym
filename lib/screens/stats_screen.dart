import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/workout_session_provider.dart';
import '../repositories/stats_repository.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/radii.dart';
import '../widgets/dashboard/stat_tile.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final StatsRepository _statsRepo = StatsRepository();
  String? _selectedExercise;
  List<String> _exerciseNames = [];
  bool _showOverall = true;

  @override
  void initState() {
    super.initState();
    _loadExerciseNames();
  }

  void _loadExerciseNames() {
    _exerciseNames = _statsRepo.getAllExerciseNames();
    if (_exerciseNames.isNotEmpty) {
      _selectedExercise = _exerciseNames.first;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<WorkoutSessionProvider>().sessions;
    final accent = accentColor(context);
    final frequency = _statsRepo.getWorkoutFrequency(8);
    final totalWorkouts = sessions.length;
    final workoutsThisWeek = _statsRepo.getWorkoutsThisWeek();
    final prs = _statsRepo.getAllExercisePRs();
    final totalPRs = prs.length;

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
        backgroundColor: surfaceColor(context),
        title: Text(
          'STATISTICS',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: textPrimaryColor(context)),
        ),
        automaticallyImplyLeading: false,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // With a sidebar taking 180px, the usable width at the 900px shell
          // breakpoint is ~720 — enough for two charts side by side, which
          // makes the [OVERALL]/[EXERCISE] toggle redundant.
          final wide =
              constraints.maxWidth >= Breakpoints.medium - 180 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.4;
          final chartHeight = wide ? 300.0 : 200.0;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSummaryCards(
                totalWorkouts,
                workoutsThisWeek,
                totalPRs,
                accent,
              ),
              const SizedBox(height: 24),
              if (wide) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildFrequencyChart(
                        frequency,
                        accent,
                        chartHeight,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildProgressionChart(accent, chartHeight),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_exerciseNames.isNotEmpty) _buildExerciseSelector(accent),
              ] else ...[
                _buildViewToggle(accent),
                const SizedBox(height: 16),
                if (_showOverall)
                  _buildFrequencyChart(frequency, accent, chartHeight)
                else
                  _buildProgressionChart(accent, chartHeight),
                const SizedBox(height: 24),
                if (!_showOverall && _exerciseNames.isNotEmpty)
                  _buildExerciseSelector(accent),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCards(int total, int thisWeek, int prs, Color accent) {
    final tiles = [
      StatTile(label: 'TOTAL WORKOUTS', value: '$total', accent: accent),
      StatTile(label: 'THIS WEEK', value: '$thisWeek', accent: accent),
      StatTile(label: 'PRS TRACKED', value: '$prs', accent: accent),
    ];
    if (MediaQuery.textScalerOf(context).scale(1) > 1.2) {
      return Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            tiles[i],
          ],
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: tiles[0]),
        const SizedBox(width: 8),
        Expanded(child: tiles[1]),
        const SizedBox(width: 8),
        Expanded(child: tiles[2]),
      ],
    );
  }

  Widget _buildViewToggle(Color accent) {
    Widget button(String label, bool selected, VoidCallback onTap) {
      return Semantics(
        container: true,
        label:
            label == '[OVERALL]' ? 'Overall statistics' : 'Exercise statistics',
        button: true,
        selected: selected,
        onTap: onTap,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.button,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected ? accentFillColor(context) : Colors.transparent,
                border: Border.all(color: accent, width: 1),
                borderRadius: AppRadius.button,
              ),
              child: Center(
                child: Text(
                  label,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: selected ? onAccentColor(context) : accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final overall = button('[OVERALL]', _showOverall, () {
      setState(() => _showOverall = true);
    });
    final exercise = button('[EXERCISE]', !_showOverall, () {
      setState(() => _showOverall = false);
    });
    if (MediaQuery.textScalerOf(context).scale(1) > 1.2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [overall, const SizedBox(height: 8), exercise],
      );
    }
    return Row(
      children: [
        Expanded(child: overall),
        const SizedBox(width: 8),
        Expanded(child: exercise),
      ],
    );
  }

  Widget _buildExerciseSelector(Color accent) {
    return DropdownButtonFormField<String>(
      initialValue: _selectedExercise,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'SELECT EXERCISE',
        border: OutlineInputBorder(borderRadius: AppRadius.field),
      ),
      items:
          _exerciseNames.map((name) {
            final pr = _statsRepo.getExercisePR(name);
            return DropdownMenuItem(
              value: name,
              child: Text(
                '$name (PR: ${pr}kg)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(fontSize: 12),
              ),
            );
          }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedExercise = value;
        });
      },
    );
  }

  Widget _buildFrequencyChart(
    Map<int, int> frequency,
    Color accent,
    double chartHeight,
  ) {
    final maxY =
        frequency.values.isEmpty
            ? 5.0
            : (frequency.values.reduce((a, b) => a > b ? a : b) + 2).toDouble();

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context), width: 1),
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'WORKOUT FREQUENCY',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            Text(
              'Last 8 Weeks',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: chartHeight,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final week = 8 - group.x.toInt();
                        return BarTooltipItem(
                          'Week $week\n${rod.toY.toInt()} workouts',
                          GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: textPrimaryColor(context),
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final week = 8 - value.toInt();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'W$week',
                              style: GoogleFonts.jetBrainsMono(fontSize: 11),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: GoogleFonts.jetBrainsMono(fontSize: 11),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: borderColor(context),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  barGroups: List.generate(8, (index) {
                    final count = frequency[index] ?? 0;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: count.toDouble(),
                          color: accent,
                          width: 20,
                          borderRadius: AppRadius.barCap,
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressionChart(Color accent, double chartHeight) {
    if (_selectedExercise == null) {
      return Container(
        decoration: BoxDecoration(
          color: surfaceColor(context),
          border: Border.all(color: borderColor(context), width: 1),
          borderRadius: AppRadius.card,
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              '> No exercise data available',
              style: GoogleFonts.jetBrainsMono(
                color: textSecondaryColor(context),
              ),
            ),
          ),
        ),
      );
    }

    final progression = _statsRepo.getExerciseProgression(_selectedExercise!);

    if (progression.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: surfaceColor(context),
          border: Border.all(color: borderColor(context), width: 1),
          borderRadius: AppRadius.card,
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Text(
                  '> No data for $_selectedExercise',
                  style: GoogleFonts.jetBrainsMono(
                    color: textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final maxWeight = progression
        .map((p) => p['maxWeight'] as double)
        .reduce((a, b) => a > b ? a : b);
    final spots =
        progression.asMap().entries.map((entry) {
          return FlSpot(
            entry.key.toDouble(),
            entry.value['maxWeight'] as double,
          );
        }).toList();

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context), width: 1),
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Text(
                '${_selectedExercise!.toUpperCase()} PROGRESSION',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              'Max Weight Over Time',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: chartHeight,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxWeight + 10,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final data = progression[spot.x.toInt()];
                          final date = data['date'] as DateTime;
                          return LineTooltipItem(
                            '${date.day}/${date.month}\n${spot.y}kg',
                            GoogleFonts.jetBrainsMono(fontSize: 11),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= progression.length) {
                            return const Text('');
                          }
                          final date =
                              progression[value.toInt()]['date'] as DateTime;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${date.day}/${date.month}',
                              style: GoogleFonts.jetBrainsMono(fontSize: 11),
                            ),
                          );
                        },
                        interval: (progression.length / 5).ceil().toDouble(),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}',
                            style: GoogleFonts.jetBrainsMono(fontSize: 11),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: borderColor(context),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: false,
                      color: accent,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: accent,
                            strokeWidth: 2,
                            strokeColor: surfaceColor(context),
                          );
                        },
                      ),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceAround,
              spacing: 24,
              runSpacing: 8,
              children: [
                _StatItem(
                  label: 'CURRENT PR',
                  value: '${progression.last['maxWeight']}kg',
                  accent: accent,
                ),
                _StatItem(
                  label: 'SESSIONS',
                  value: '${progression.length}',
                  accent: accent,
                ),
                _StatItem(
                  label: 'PROGRESS',
                  value: _calculateProgress(progression),
                  accent: accent,
                  valueColor: _getProgressColor(progression),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _calculateProgress(List<Map<String, dynamic>> progression) {
    if (progression.length < 2) return '-';
    final first = progression.first['maxWeight'] as double;
    final last = progression.last['maxWeight'] as double;
    if (first == 0) return '-';
    final diff = last - first;
    final sign = diff >= 0 ? '+' : '';
    return '$sign${diff.toStringAsFixed(1)}kg';
  }

  Color _getProgressColor(List<Map<String, dynamic>> progression) {
    if (progression.length < 2) return textSecondaryColor(context);
    final first = progression.first['maxWeight'] as double;
    final last = progression.last['maxWeight'] as double;
    if (last > first) return successColor(context);
    if (last < first) return errorColor(context);
    return textSecondaryColor(context);
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final Color? valueColor;

  const _StatItem({
    required this.label,
    required this.value,
    required this.accent,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: valueColor ?? accent,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: textSecondaryColor(context),
          ),
        ),
      ],
    );
  }
}
