import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String legacyTrainingBlockId(String splitId) => _uuid.v5(
  Namespace.url.value,
  'https://opengym.app/splits/${splitId.toLowerCase()}/training-blocks/legacy-v1',
);

String legacyTrainingWeekId(String splitId, int number) {
  if (number < 1) throw ArgumentError.value(number, 'number');
  return _uuid.v5(legacyTrainingBlockId(splitId), number.toString());
}

String workoutProgressId(String splitId, String planId) => _uuid.v5(
  Namespace.url.value,
  'https://opengym.app/splits/${splitId.toLowerCase()}/plans/${planId.toLowerCase()}/progress-v1',
);

String initialProgressRevision(String splitId, String planId) =>
    _uuid.v5(workoutProgressId(splitId, planId), 'initial-v1');

/// Replicas allocating the same lazy slot independently must choose one ID.
String lazyTrainingWeekId(String splitId, String blockId, int number) {
  if (number < 1) throw ArgumentError.value(number, 'number');
  return _uuid.v5(
    Namespace.url.value,
    'https://opengym.app/splits/${splitId.toLowerCase()}/blocks/${blockId.toLowerCase()}/lazy-weeks/$number',
  );
}

/// The block that adopts live work when a replica deletes the block it was in.
/// Derived from the deleted block's id so replicas rescuing the same block
/// choose one ID.
String rescuedTrainingBlockId(String blockId) => _uuid.v5(
  Namespace.url.value,
  'https://opengym.app/blocks/${blockId.toLowerCase()}/rescued-v1',
);
