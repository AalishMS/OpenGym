import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/training_week_session_resolver.dart';

void main() {
  final now = DateTime.utc(2026);
  final blocks = [
    for (var i = 1; i <= 3; i++)
      TrainingBlock(
        id: 'b$i',
        splitId: 's',
        name: 'Block $i',
        position: i,
        createdAt: now,
      ),
  ];
  final weeks = [
    for (var b = 1; b <= 3; b++)
      for (var n = 1; n <= 3; n++)
        TrainingWeek(
          id: 'b$b-w$n',
          splitId: 's',
          blockId: 'b$b',
          number: n,
          createdAt: now,
        ),
  ];
  WorkoutSession log(
    String id,
    String week, {
    bool completed = true,
    bool running = false,
    String plan = 'p',
    DateTime? at,
  }) => WorkoutSession(
    id: id,
    splitId: 's',
    planId: plan,
    planName: plan,
    trainingWeekId: week,
    weekNumber: weeks.firstWhere((w) => w.id == week).number,
    date: at ?? now,
    isCompleted: completed,
    startedAt: running ? now : null,
    timerStartedAt: running ? now : null,
    exercises: [],
  );

  test('later weeks inherit the preceding week within their own block', () {
    final rows = [
      log('match', 'b2-w1'),
      log('wrong-number', 'b1-w2'),
      log('draft', 'b2-w1', completed: false),
      log('other-plan', 'b2-w1', plan: 'other'),
    ];
    final source = TrainingWeekSessionResolver.source(
      splitId: 's',
      planId: 'p',
      weekId: 'b2-w2',
      blocks: blocks,
      weeks: weeks,
      sessions: rows,
    );
    expect(source!.id, 'match');
    expect(
      TrainingWeekSessionResolver.source(
        splitId: 's',
        planId: 'p',
        weekId: 'b3-w2',
        blocks: blocks,
        weeks: weeks,
        sessions: rows,
      ),
      isNull,
    );
  });
  test('new block first week keeps matching Week 1 inheritance', () {
    expect(
      TrainingWeekSessionResolver.source(
        splitId: 's',
        planId: 'p',
        weekId: 'b2-w1',
        blocks: blocks,
        weeks: weeks,
        sessions: [log('first', 'b1-w1'), log('last', 'b1-w3')],
      )!.id,
      'first',
    );
  });
  test(
    'first supplied sparse week has no source; later weeks use previous supplied slot',
    () {
      final sparse =
          weeks.where((w) => w.blockId == 'b1' && w.number >= 2).toList();
      final rows = [log('old', 'b1-w1'), log('source', 'b1-w2')];
      expect(
        TrainingWeekSessionResolver.source(
          splitId: 's',
          planId: 'p',
          weekId: 'b1-w2',
          blocks: [blocks.first],
          weeks: sparse,
          sessions: rows,
        ),
        isNull,
      );
      expect(
        TrainingWeekSessionResolver.source(
          splitId: 's',
          planId: 'p',
          weekId: 'b1-w3',
          blocks: [blocks.first],
          weeks: sparse,
          sessions: rows,
        )!.id,
        'source',
      );
    },
  );
  test(
    'saved destination prioritizes exact ID, running draft, other draft, then latest completion',
    () {
      final rows = [
        log('complete', 'b2-w1'),
        log(
          'draft',
          'b2-w1',
          completed: false,
          at: now.add(const Duration(days: 1)),
        ),
        log('running', 'b2-w1', completed: false, running: true),
      ];
      WorkoutSession? destination([String? id]) =>
          TrainingWeekSessionResolver.destination(
            splitId: 's',
            planId: 'p',
            weekId: 'b2-w1',
            sessions: rows,
            sessionId: id,
          );
      expect(destination()!.id, 'running');
      expect(destination('complete')!.id, 'complete');
      rows.removeLast();
      expect(destination()!.id, 'draft');
      rows.removeLast();
      expect(destination()!.id, 'complete');
    },
  );
  test(
    'Previous uses earlier structural slots while inheritance matches week number',
    () {
      final rows = [
        log('last', 'b1-w3'),
        log('matching', 'b1-w1'),
        log('future', 'b2-w2'),
      ];
      final earlier = TrainingWeekSessionResolver.earlierSessions(
        splitId: 's',
        planId: 'p',
        weekId: 'b2-w1',
        blocks: blocks,
        weeks: weeks,
        sessions: rows,
      );
      expect(earlier.map((s) => s.id), ['last', 'matching']);
    },
  );
}
