import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../data/exercise_library.dart';
import '../models/exercise_definition.dart';

/// Account-wide, offline-first catalog. Only custom entries and overrides of
/// bundled entries need storage. Names are search terms; IDs are identity.
class ExerciseCatalog {
  static const boxName = 'exercise_definitions';
  static const _uuid = Uuid();
  static Box<dynamic>? _cachedBox;
  static Map<String, ExerciseDefinition>? _definitions;
  static final Map<String, String> _canonical = {};
  static Map<String, Set<String>>? _names;

  static void _invalidate() {
    _definitions = null;
    _names = null;
    _canonical.clear();
  }

  static Map<String, ExerciseDefinition> get _byId {
    final box = Hive.isBoxOpen(boxName) ? Hive.box<dynamic>(boxName) : null;
    if (!identical(box, _cachedBox)) {
      _cachedBox = box;
      _invalidate();
    }
    return _definitions ??= {
      for (final d in ExerciseLibrary.definitions) d.id: d,
      for (final d in stored) d.id: d,
    };
  }

  static String normalize(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// Deterministic only for legacy data, so two devices migrating the same
  /// account agree. Explicitly created custom exercises receive UUID4 IDs.
  static String legacyId(String name) => _uuid.v5(
    Namespace.url.value,
    'https://opengym.app/legacy-exercises/${normalize(name)}',
  );

  static Future<void> open() async {
    if (!Hive.isBoxOpen(boxName)) await Hive.openBox<dynamic>(boxName);
  }

  static List<ExerciseDefinition> get stored =>
      !Hive.isBoxOpen(boxName)
          ? []
          : Hive.box<dynamic>(boxName).values
              .map(
                (v) => ExerciseDefinition.fromJson(
                  Map<String, dynamic>.from(v as Map),
                ),
              )
              .toList();

  static List<ExerciseDefinition> get all => _byId.values.toList();

  static ExerciseDefinition? getById(String id) => _byId[id];

  static String canonicalId(String id) {
    final definitions = _byId;
    if (_canonical.containsKey(id)) return _canonical[id]!;
    final path = <String>[];
    var current = id;
    while (true) {
      final cycle = path.indexOf(current);
      if (cycle >= 0) {
        // Opposing offline merges converge without losing either log. Keeping
        // the smallest cycle ID gives every device the same representative.
        final ids = path.sublist(cycle)..sort();
        for (final entry in path) {
          _canonical[entry] = ids.first;
        }
        return ids.first;
      }
      path.add(current);
      final next = definitions[current]?.mergedIntoId;
      // Catalog rows can arrive separately or be interrupted mid-pull. Keep
      // the last known movement usable until its target metadata is delivered;
      // never hide it behind an ID which the picker cannot display.
      if (next == null || !definitions.containsKey(next)) {
        for (final entry in path) {
          _canonical[entry] = current;
        }
        return current;
      }
      current = next;
    }
  }

  static ExerciseDefinition? findByName(String name) {
    final definitions = _byId;
    final names = _names ??= <String, Set<String>>{};
    if (names.isEmpty) {
      for (final d in definitions.values) {
        for (final label in [d.name, ...d.aliases]) {
          names.putIfAbsent(normalize(label), () => {}).add(d.id);
        }
      }
    }
    final ids = (names[normalize(name)] ?? <String>{}).map(canonicalId).toSet();
    return ids.length == 1 ? definitions[ids.single] : null;
  }

  static String identity(String name, [String? exerciseId]) {
    if (exerciseId != null && exerciseId.isNotEmpty) {
      return canonicalId(exerciseId);
    }
    if (_byId.containsKey(name) ||
        name.startsWith('builtin:') ||
        Uuid.isValidUUID(fromString: name)) {
      return canonicalId(name);
    }
    return canonicalId(findByName(name)?.id ?? legacyId(name));
  }

  /// How an occurrence is measured, by its canonical identity rather than its
  /// name snapshot. Renaming an occurrence keeps its ID, so a renamed hold
  /// still stores seconds, and a custom exercise named like a hold does not.
  static ExerciseKind kindOf(String name, [String? exerciseId]) =>
      ExerciseLibrary.kindOfId(identity(name, exerciseId));

  /// Whether an occurrence is a hold whose sets store seconds in `reps`.
  static bool isTimed(String name, [String? exerciseId]) =>
      kindOf(name, exerciseId) == ExerciseKind.timed;

  static String displayName(String id, String fallback) =>
      getById(canonicalId(id))?.name ?? fallback;

  static List<ExerciseDefinition> get active =>
      all.where((d) => canonicalId(d.id) == d.id).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  static List<ExerciseDefinition> search(String query) {
    final key = normalize(query);
    final ids =
        all
            .where(
              (d) =>
                  normalize(d.name).contains(key) ||
                  d.aliases.any((a) => normalize(a).contains(key)),
            )
            .map((d) => canonicalId(d.id))
            .toSet();
    return active.where((d) => ids.contains(d.id)).toList();
  }

  /// Suggestions never establish identity. The user chooses a movement or
  /// explicitly creates their own entry, including ambiguous abbreviations.
  static List<ExerciseDefinition> suggestions(String query) {
    Set<String> words(String value) =>
        normalize(value)
            .split(RegExp(r'[^a-z0-9]+'))
            .where((w) => w.length > 1)
            .map(
              (w) => switch (w) {
                'db' => 'dumbbell',
                'bb' => 'barbell',
                _ => w,
              },
            )
            .toSet();
    final wanted = words(query);
    if (wanted.isEmpty) return [];
    final ranked = <({ExerciseDefinition definition, double score})>[];
    for (final d in active) {
      var score = 0.0;
      for (final label in [d.name, ...d.aliases]) {
        final candidate = words(label);
        final shared = wanted.intersection(candidate).length;
        final value = shared / wanted.union(candidate).length;
        if (value > score) score = value;
      }
      if (score >= 0.45) ranked.add((definition: d, score: score));
    }
    ranked.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score == 0
          ? a.definition.name.compareTo(b.definition.name)
          : score;
    });
    return ranked.take(3).map((r) => r.definition).toList();
  }

  static Future<void> put(
    ExerciseDefinition value, {
    bool Function()? isCurrent,
  }) async {
    await open();
    if (isCurrent != null && !isCurrent()) {
      throw StateError('The exercise account changed.');
    }
    // Validate before touching the live box, including values from sync.
    ExerciseDefinition.fromJson(value.toJson());
    await Hive.box<dynamic>(boxName).put(value.id, value.toJson());
    _invalidate();
  }

  static Future<ExerciseDefinition> createCustom(
    String name, {
    String? userId,
  }) async {
    if (stored.any((d) => d.userId != userId)) {
      throw StateError('The exercise catalog belongs to another account.');
    }
    final trimmed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty || trimmed.length > 100) {
      throw const FormatException('Use an exercise name of 1–100 characters.');
    }
    final existing = findByName(trimmed);
    if (existing != null) return existing;
    final value = ExerciseDefinition(
      id: _uuid.v4(),
      name: trimmed,
      userId: userId,
      updatedAt: DateTime.now(),
      dirty: true,
    );
    await put(value);
    return value;
  }

  static Future<String> ensure(
    String name, {
    String? exerciseId,
    String? userId,
    bool Function()? isCurrent,
  }) async {
    final id = exerciseId ?? findByName(name)?.id ?? legacyId(name);
    if (getById(id) == null) {
      await put(
        ExerciseDefinition(
          id: id,
          name: name.trim(),
          userId: userId,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          dirty: true,
        ),
        isCurrent: isCurrent,
      );
    }
    return id;
  }

  static Future<void> rename(String id, String name, {String? userId}) async {
    final current = getById(id);
    final trimmed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (current == null ||
        current.builtIn ||
        current.userId != userId ||
        current.mergedIntoId != null ||
        stored.any((d) => d.userId != userId)) {
      throw StateError('The exercise changed.');
    }
    if (trimmed.isEmpty || trimmed.length > 100) {
      throw const FormatException('Use an exercise name of 1–100 characters.');
    }
    if (all.any(
      (d) =>
          canonicalId(d.id) != id &&
          [d.name, ...d.aliases].any((a) => normalize(a) == normalize(trimmed)),
    )) {
      throw const FormatException(
        'This exercise already exists. Use Merge instead.',
      );
    }
    await put(
      current.copyWith(
        name: trimmed,
        aliases: {...current.aliases, current.name}.toList(),
        updatedAt: DateTime.now(),
        dirty: true,
      ),
    );
  }

  /// One durable redirect makes every past/future reference resolve together.
  /// No sets or historical name snapshots are changed or removed.
  static Future<void> merge(
    String sourceId,
    String targetId, {
    String? userId,
  }) async {
    final source = getById(canonicalId(sourceId));
    final target = getById(canonicalId(targetId));
    if (source == null || target == null || source.id == target.id) {
      throw StateError('Choose two different exercises to merge.');
    }
    if (stored.any((d) => d.userId != userId)) {
      throw StateError('The exercise catalog belongs to another account.');
    }
    await put(
      source.copyWith(
        mergedIntoId: target.id,
        userId: userId,
        updatedAt: DateTime.now(),
        dirty: true,
      ),
    );
    await Hive.box<dynamic>(boxName).flush();
  }

  static Future<void> clear() async {
    if (Hive.isBoxOpen(boxName)) await Hive.box<dynamic>(boxName).clear();
    _invalidate();
  }
}
