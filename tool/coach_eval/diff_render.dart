// ProposalDiff as text for the eval report: the proposal card's summary,
// change counts for the "minimal change" grade, and a Markdown diff that
// mirrors the review screen.

import 'package:gymapp/models/coach_proposal.dart';
import 'package:gymapp/services/coach/proposal_diff.dart';

/// `CoachProposalItem.summary`: "2 plans changed, 1 added".
String diffSummary(ProposalDiff diff) {
  final parts = [
    for (final (kind, verb) in const [
      (DiffKind.changed, 'changed'),
      (DiffKind.added, 'added'),
      (DiffKind.removed, 'removed'),
    ])
      if (diff.count(kind) > 0) (diff.count(kind), verb),
  ];
  return [
    for (var index = 0; index < parts.length; index++)
      index == 0
          ? '${parts[index].$1} ${parts[index].$1 == 1 ? 'plan' : 'plans'} '
              '${parts[index].$2}'
          : '${parts[index].$1} ${parts[index].$2}',
  ].join(', ');
}

/// Plans and exercises touched, for judging how small the change was.
Map<String, int> diffCounts(ProposalDiff diff) {
  final exercises = [
    for (final plan in diff.plans)
      if (plan.kind == DiffKind.changed) ...plan.exercises,
  ];
  return {
    'plansChanged': diff.count(DiffKind.changed),
    'plansAdded': diff.count(DiffKind.added),
    'plansRemoved': diff.count(DiffKind.removed),
    'exercisesAdded': exercises.where((e) => e.kind == DiffKind.added).length,
    'exercisesRemoved':
        exercises.where((e) => e.kind == DiffKind.removed).length,
    'exercisesChanged':
        exercises
            .where(
              (e) =>
                  e.kind == DiffKind.changed ||
                  (e.kind == DiffKind.unchanged && e.moved),
            )
            .length,
  };
}

String sets(List<CoachSet> sets) {
  if (sets.isEmpty) return '';
  final first = sets.first;
  if (sets.every((set) => set == first)) {
    return '${sets.length}×${first.reps} @ ${_kg(first.kg)}';
  }
  return sets.map((set) => '${set.reps}@${_kg(set.kg)}').join(', ');
}

String _kg(double kg) => kg == 0 ? 'no target' : '${coachNumber(kg)} kg';

/// One block per affected plan, marked like the review screen: `+` added,
/// `-` removed, `~` changed, `=` unchanged.
String renderDiff(ProposalDiff diff) {
  final lines = <String>[];
  for (final plan in diff.plans) {
    final title =
        plan.renamed ? '${plan.previousName} → ${plan.name}' : plan.name;
    lines.add('${plan.kind.name.toUpperCase()} · $title');
    for (final exercise in plan.exercises) {
      final custom = exercise.custom ? ' [custom]' : '';
      final moved = exercise.moved ? ' (moved)' : '';
      final line = switch (exercise.kind) {
        DiffKind.added =>
          '  + ${exercise.name}$custom  ${sets(exercise.after)}',
        DiffKind.removed => '  - ${exercise.name}  ${sets(exercise.before)}',
        DiffKind.changed =>
          '  ~ ${exercise.name}$custom  '
              '${exercise.setsChanged ? '${sets(exercise.before)} → ${sets(exercise.after)}' : sets(exercise.after)}',
        DiffKind.unchanged =>
          '  = ${exercise.name}$custom  ${sets(exercise.after)}$moved',
      };
      lines.add(line);
      if (exercise.noteChanged && exercise.noteAfter != null) {
        lines.add('      note: ${exercise.noteAfter}');
      }
    }
  }
  return lines.join('\n');
}
