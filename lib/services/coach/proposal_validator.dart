import 'dart:convert';

import '../../data/exercise_library.dart';
import '../../models/coach_proposal.dart';
import '../../models/workout_plan.dart';

/// The validator's verdict: a [reply] when the output is usable, otherwise
/// [errors] written for the model to fix on its one retry.
class ProposalValidationResult {
  final CoachReply? reply;
  final List<String> errors;

  const ProposalValidationResult._(this.reply, this.errors);

  factory ProposalValidationResult.valid(CoachReply reply) =>
      ProposalValidationResult._(reply, const []);

  factory ProposalValidationResult.invalid(List<String> errors) =>
      ProposalValidationResult._(null, List.unmodifiable(errors));

  bool get isValid => reply != null;
}

/// Checks a model answer against the contract in `docs/coach.md` and the
/// [CoachSnapshot] the request was built from.
///
/// Never throws on bad model output: every problem becomes an error string
/// that names its JSON path, so one retry can fix all of them at once.
class ProposalValidator {
  static const int maxSetsPerExercise = 10;
  static const int maxReps = 100;
  static const double maxKg = 500;
  static const int maxExercisesPerPlan = 15;
  static const int maxPlansInNewSplit = 7;
  static const int maxPlansInSplit = 10;
  static const int maxPlanNameLength = 40;
  static const int maxSplitNameLength = 24;
  static const int maxExerciseNameLength = 40;
  static const int maxNoteLength = 200;

  const ProposalValidator();

  ProposalValidationResult validate(String output, CoachSnapshot snapshot) =>
      _Run(snapshot).validate(output);

  /// Up to [limit] library names closest to [query] by word overlap, after
  /// expanding common gym abbreviations. Best first; empty when nothing
  /// shares a word.
  static List<String> closestExercises(
    String query, {
    Iterable<String>? candidates,
    int limit = 3,
  }) {
    final wanted = _tokens(query);
    if (wanted.isEmpty) return const [];
    final scored = <(String, double)>[];
    for (final candidate in candidates ?? ExerciseLibrary.allExercises) {
      final tokens = _tokens(candidate);
      final shared = wanted.intersection(tokens).length;
      if (shared == 0) continue;
      scored.add((candidate, shared / wanted.union(tokens).length));
    }
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });
    return [for (final entry in scored.take(limit)) entry.$1];
  }

  static const Map<String, List<String>> _aliases = {
    'db': ['dumbbell'],
    'bb': ['barbell'],
    'ohp': ['overhead', 'press'],
    'rdl': ['romanian', 'deadlift'],
    'bss': ['bulgarian', 'split', 'squat'],
    'pullup': ['pull', 'up'],
    'chinup': ['chin', 'up'],
    'pushup': ['push', 'up'],
    'tri': ['tricep'],
    'bi': ['bicep'],
  };

  static Set<String> _tokens(String name) {
    final tokens = <String>{};
    for (final raw in name.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
      if (raw.isEmpty) continue;
      final expanded = _aliases[raw];
      if (expanded != null) {
        tokens.addAll(expanded);
      } else if (raw.length > 3 && raw.endsWith('s') && !raw.endsWith('ss')) {
        // Plurals: "Raises" finds "Raise", "Curls" finds "Curl".
        tokens.add(raw.substring(0, raw.length - 1));
      } else {
        tokens.add(raw);
      }
    }
    return tokens;
  }
}

/// One validation pass. Holds the error list so each check can report and
/// carry on, rather than stopping at the first problem.
class _Run {
  final CoachSnapshot snapshot;
  final List<String> errors = [];

  late final Map<String, String> _library = {
    for (final name in ExerciseLibrary.allExercises) _key(name): name,
  };
  late final Map<String, String> _custom = {
    for (final name in snapshot.customExercises) _key(name): name,
  };

  _Run(this.snapshot);

  ProposalValidationResult validate(String output) {
    final Object? decoded;
    try {
      decoded = jsonDecode(_stripFence(output));
    } on FormatException {
      return ProposalValidationResult.invalid([
        'The output is not valid JSON. Answer with one JSON object that has '
            '"reply" and "proposal".',
      ]);
    }
    if (decoded is! Map<String, dynamic>) {
      return ProposalValidationResult.invalid([
        'The output must be a JSON object with "reply" and "proposal".',
      ]);
    }

    final reply = decoded['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      errors.add('reply: must be a non-empty string.');
    }
    final rawProposal = decoded['proposal'];
    ValidatedProposal? proposal;
    if (rawProposal != null) {
      if (rawProposal is Map<String, dynamic>) {
        proposal = _proposal(rawProposal);
      } else {
        errors.add('proposal: must be an object or null.');
      }
    }

    if (errors.isNotEmpty) return ProposalValidationResult.invalid(errors);
    return ProposalValidationResult.valid(
      CoachReply(reply: (reply as String).trim(), proposal: proposal),
    );
  }

  ValidatedProposal? _proposal(Map<String, dynamic> json) {
    final target = switch (json['target']) {
      'active_split' => CoachTarget.activeSplit,
      'new_split' => CoachTarget.newSplit,
      _ => null,
    };
    if (target == null) {
      errors.add('proposal.target: must be "active_split" or "new_split".');
      return null;
    }
    final newSplit = target == CoachTarget.newSplit;
    final splitName = newSplit ? _newSplitName(json['newSplitName']) : null;

    final rawPlans = json['plans'] ?? const <Object?>[];
    if (rawPlans is! List) {
      errors.add('proposal.plans: must be a list.');
      return null;
    }
    final removed = newSplit ? <WorkoutPlan>[] : _removed(json);
    final editedIds = <String>{};
    final plans = <CoachPlan>[];
    for (var index = 0; index < rawPlans.length; index++) {
      final plan = _plan(
        rawPlans[index],
        'proposal.plans[$index]',
        newSplit: newSplit,
        editedIds: editedIds,
        removed: removed,
      );
      if (plan != null) plans.add(plan);
    }
    if (newSplit &&
        json['removePlanRefs'] is List &&
        (json['removePlanRefs'] as List).isNotEmpty) {
      errors.add(
        'proposal.removePlanRefs: must be empty when target is "new_split".',
      );
    }
    if (errors.isNotEmpty) return null;

    _checkPlanCount(plans, removed, newSplit: newSplit);
    _checkPlanNames(plans, removed, newSplit: newSplit);
    if (!newSplit && removed.isEmpty && plans.every(_isUnchanged)) {
      errors.add(
        'proposal: changes nothing. Use "proposal": null when no plan '
        'change is needed.',
      );
    }
    if (errors.isNotEmpty) return null;

    return ValidatedProposal(
      target: target,
      newSplitName: splitName,
      plans: plans,
      removedPlans: removed,
      snapshot: snapshot,
    );
  }

  String? _newSplitName(Object? raw) {
    const path = 'proposal.newSplitName';
    if (snapshot.splitNames.length >= snapshot.maxSplits) {
      errors.add(
        // Not "use active_split instead": on the eval that hint made the
        // retry rewrite every plan in the active split.
        '$path: the user already has ${snapshot.maxSplits} splits, the '
        'maximum, so no split can be created. Answer with "proposal": null '
        'and tell the user to delete a split first. Change the active split '
        'only if the user asked for that.',
      );
      return null;
    }
    if (raw is! String || raw.trim().isEmpty) {
      errors.add('$path: required when target is "new_split".');
      return null;
    }
    final name = raw.trim();
    if (name.length > ProposalValidator.maxSplitNameLength) {
      errors.add(
        '$path: "$name" is longer than '
        '${ProposalValidator.maxSplitNameLength} characters.',
      );
      return null;
    }
    if (snapshot.splitNames.any((n) => n.toLowerCase() == name.toLowerCase())) {
      errors.add('$path: a split named "$name" already exists.');
      return null;
    }
    return name;
  }

  List<WorkoutPlan> _removed(Map<String, dynamic> json) {
    final raw = json['removePlanRefs'] ?? const <Object?>[];
    if (raw is! List) {
      errors.add('proposal.removePlanRefs: must be a list of refs.');
      return [];
    }
    final removed = <WorkoutPlan>[];
    for (var index = 0; index < raw.length; index++) {
      final plan = _resolveRef(raw[index], 'proposal.removePlanRefs[$index]');
      if (plan != null && !removed.contains(plan)) removed.add(plan);
    }
    return removed;
  }

  CoachPlan? _plan(
    Object? raw,
    String path, {
    required bool newSplit,
    required Set<String> editedIds,
    required List<WorkoutPlan> removed,
  }) {
    if (raw is! Map<String, dynamic>) {
      errors.add('$path: must be an object.');
      return null;
    }
    final errorCount = errors.length;

    WorkoutPlan? existing;
    final ref = raw['ref'];
    if (ref != null) {
      if (newSplit) {
        errors.add('$path.ref: must be null when target is "new_split".');
      } else {
        existing = _resolveRef(ref, '$path.ref');
        if (existing != null) {
          if (!editedIds.add(existing.id!)) {
            errors.add('$path.ref: "$ref" appears in more than one plan.');
          }
          if (removed.contains(existing)) {
            errors.add(
              '$path.ref: "$ref" is also in removePlanRefs. Edit it or '
              'remove it, not both.',
            );
          }
        }
      }
    }

    final name = _text(
      raw['name'],
      '$path.name',
      maxLength: ProposalValidator.maxPlanNameLength,
    );
    final exercises = _exercises(raw['exercises'], '$path.exercises');

    if (errors.length != errorCount || name == null || exercises == null) {
      return null;
    }
    return CoachPlan(existing: existing, name: name, exercises: exercises);
  }

  List<CoachExercise>? _exercises(Object? raw, String path) {
    if (raw is! List) {
      errors.add('$path: must be a list.');
      return null;
    }
    if (raw.isEmpty || raw.length > ProposalValidator.maxExercisesPerPlan) {
      errors.add(
        '$path: a plan needs 1 to ${ProposalValidator.maxExercisesPerPlan} '
        'exercises, not ${raw.length}.',
      );
      return null;
    }
    final errorCount = errors.length;
    final exercises = <CoachExercise>[];
    final seen = <String>{};
    for (var index = 0; index < raw.length; index++) {
      final exercise = _exercise(raw[index], '$path[$index]');
      if (exercise == null) continue;
      if (!seen.add(_key(exercise.name))) {
        errors.add(
          '$path[$index].name: "${exercise.name}" is already in this plan. '
          'Put all of its sets in one entry.',
        );
        continue;
      }
      exercises.add(exercise);
    }
    return errors.length == errorCount ? exercises : null;
  }

  CoachExercise? _exercise(Object? raw, String path) {
    if (raw is! Map<String, dynamic>) {
      errors.add('$path: must be an object.');
      return null;
    }
    final errorCount = errors.length;
    final custom = raw['custom'];
    if (custom != null && custom is! bool) {
      errors.add('$path.custom: must be true or false.');
    }
    final resolved = _exerciseName(raw['name'], '$path.name', custom == true);
    final sets = _sets(raw['sets'], '$path.sets');
    final note = _note(raw['note'], '$path.note');
    if (errors.length != errorCount || resolved == null || sets == null) {
      return null;
    }
    return CoachExercise(
      name: resolved.name,
      sets: sets,
      note: note,
      custom: resolved.custom,
    );
  }

  ({String name, bool custom})? _exerciseName(
    Object? raw,
    String path,
    bool customAllowed,
  ) {
    if (raw is! String || raw.trim().isEmpty) {
      errors.add('$path: must be a non-empty string.');
      return null;
    }
    final key = _key(raw);
    final library = _library[key];
    if (library != null) return (name: library, custom: false);
    final known = _custom[key];
    if (known != null) return (name: known, custom: true);

    final name = raw.trim().replaceAll(_spaces, ' ');
    if (customAllowed) {
      if (name.length > ProposalValidator.maxExerciseNameLength) {
        errors.add(
          '$path: custom names must be at most '
          '${ProposalValidator.maxExerciseNameLength} characters.',
        );
        return null;
      }
      return (name: name, custom: true);
    }
    final closest = ProposalValidator.closestExercises(name);
    errors.add(
      '$path: "$name" is not in the library. '
      '${closest.isEmpty ? 'Use a name from "library".' : 'Closest: ${closest.map((n) => '"$n"').join(', ')}.'}'
      ' Set "custom": true only if the user asked for this exercise by name.',
    );
    return null;
  }

  List<CoachSet>? _sets(Object? raw, String path) {
    if (raw is! List) {
      errors.add('$path: must be a list of {"reps", "kg"} objects.');
      return null;
    }
    if (raw.isEmpty || raw.length > ProposalValidator.maxSetsPerExercise) {
      errors.add(
        '$path: an exercise needs 1 to '
        '${ProposalValidator.maxSetsPerExercise} sets, not ${raw.length}.',
      );
      return null;
    }
    final errorCount = errors.length;
    final sets = <CoachSet>[];
    for (var index = 0; index < raw.length; index++) {
      final set = raw[index];
      final setPath = '$path[$index]';
      if (set is! Map<String, dynamic>) {
        errors.add('$setPath: must be a {"reps", "kg"} object.');
        continue;
      }
      final reps = set['reps'];
      final kg = set['kg'] ?? 0;
      final wholeReps = reps is num && reps == reps.roundToDouble();
      if (!wholeReps || reps < 1 || reps > ProposalValidator.maxReps) {
        errors.add(
          '$setPath.reps: must be a whole number from 1 to '
          '${ProposalValidator.maxReps}.',
        );
      }
      if (kg is! num || kg < 0 || kg > ProposalValidator.maxKg) {
        errors.add(
          '$setPath.kg: must be a number from 0 to '
          '${coachNumber(ProposalValidator.maxKg)}. Use 0 for no weight '
          'target.',
        );
      }
      if (errors.length == errorCount) {
        sets.add(
          CoachSet(
            reps: (reps as num).toInt(),
            kg: ((kg as num) * 4).round() / 4,
          ),
        );
      }
    }
    return errors.length == errorCount ? sets : null;
  }

  String? _note(Object? raw, String path) {
    if (raw == null) return null;
    if (raw is! String) {
      errors.add('$path: must be a string or null.');
      return null;
    }
    final note = coachNote(raw);
    if (note != null && note.length > ProposalValidator.maxNoteLength) {
      errors.add(
        '$path: must be at most ${ProposalValidator.maxNoteLength} '
        'characters.',
      );
      return null;
    }
    return note;
  }

  String? _text(Object? raw, String path, {required int maxLength}) {
    if (raw is! String || raw.trim().isEmpty) {
      errors.add('$path: must be a non-empty string.');
      return null;
    }
    final text = raw.trim();
    if (text.length > maxLength) {
      errors.add('$path: must be at most $maxLength characters.');
      return null;
    }
    return text;
  }

  WorkoutPlan? _resolveRef(Object? raw, String path) {
    final plan = raw is String ? snapshot.planForRef(raw) : null;
    if (plan == null) {
      final known =
          snapshot.plans.isEmpty
              ? 'This split has no plans, so use "ref": null.'
              : 'Valid refs: ${[for (var i = 0; i < snapshot.plans.length; i++) CoachSnapshot.refAt(i)].join(', ')}.';
      errors.add('$path: "$raw" is not a plan ref. $known');
    }
    return plan;
  }

  void _checkPlanCount(
    List<CoachPlan> plans,
    List<WorkoutPlan> removed, {
    required bool newSplit,
  }) {
    if (newSplit) {
      if (plans.isEmpty ||
          plans.length > ProposalValidator.maxPlansInNewSplit) {
        errors.add(
          'proposal.plans: a new split needs 1 to '
          '${ProposalValidator.maxPlansInNewSplit} plans, not ${plans.length}.',
        );
      }
      return;
    }
    final resulting =
        snapshot.plans.length -
        removed.length +
        plans.where((plan) => plan.isNew).length;
    if (resulting > ProposalValidator.maxPlansInSplit) {
      // The exact room left: told only "keep between 1 and 10", the retry
      // on the eval still added one plan too many.
      final room =
          ProposalValidator.maxPlansInSplit -
          (snapshot.plans.length - removed.length);
      errors.add(
        'proposal: the split would have $resulting plans after this change, '
        'and the maximum is ${ProposalValidator.maxPlansInSplit}. It has '
        '${snapshot.plans.length} now, so add at most ${room < 0 ? 0 : room} '
        'new ${room == 1 ? 'plan' : 'plans'}, and say in the reply what '
        "didn't fit.",
      );
    } else if (resulting < 1) {
      errors.add(
        'proposal: the split would have $resulting plans after this change. '
        'Keep between 1 and ${ProposalValidator.maxPlansInSplit}.',
      );
    }
  }

  void _checkPlanNames(
    List<CoachPlan> plans,
    List<WorkoutPlan> removed, {
    required bool newSplit,
  }) {
    final edited = {for (final plan in plans) plan.existing};
    final taken = <String>{
      if (!newSplit)
        for (final plan in snapshot.plans)
          if (!edited.contains(plan) && !removed.contains(plan))
            plan.name.trim().toLowerCase(),
    };
    for (var index = 0; index < plans.length; index++) {
      final name = plans[index].name;
      if (!taken.add(name.toLowerCase())) {
        errors.add(
          'proposal.plans[$index].name: "$name" is already a plan name in '
          'this split. Plan names must be unique.',
        );
      }
    }
  }

  bool _isUnchanged(CoachPlan plan) {
    final existing = plan.existing;
    if (existing == null || existing.name.trim() != plan.name) return false;
    if (existing.exercises.length != plan.exercises.length) return false;
    for (var index = 0; index < plan.exercises.length; index++) {
      final before = existing.exercises[index];
      final after = plan.exercises[index];
      if (_key(before.name) != _key(after.name) ||
          coachNote(before.note) != after.note) {
        return false;
      }
      final beforeSets = coachSetsOf(before);
      if (beforeSets.length != after.sets.length) return false;
      for (var set = 0; set < beforeSets.length; set++) {
        if (beforeSets[set] != after.sets[set]) return false;
      }
    }
    return true;
  }

  static final RegExp _spaces = RegExp(r'\s+');

  static String _key(String name) =>
      name.trim().replaceAll(_spaces, ' ').toLowerCase();

  /// Tolerates a ```json fence, which models add even under a response schema.
  static String _stripFence(String output) {
    final trimmed = output.trim();
    final match = RegExp(
      r'^```[a-zA-Z]*\s*\n?([\s\S]*?)\n?```$',
    ).firstMatch(trimmed);
    return match == null ? trimmed : match.group(1)!.trim();
  }
}
