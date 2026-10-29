import 'package:hive/hive.dart';

const _boxName = 'training_recovery_snapshots';

// Keep safety artifacts outside training_operations: snapshotting that box
// must not recursively embed earlier safety copies or clear its own journal.
Future<Box<String>> _box() => Hive.openBox<String>(_boxName);

String snapshotPath(String kind, String ownerKey) =>
    'hive://training-recovery/$kind/$ownerKey';
Future<bool> exists(String path) async => (await _box()).containsKey(path);
Future<String> read(String path) async {
  final value = (await _box()).get(path);
  if (value == null) {
    throw StateError('The training safety copy is unavailable.');
  }
  return value;
}

Future<void> write(String path, String value) async {
  final box = await _box();
  await box.put(path, value);
  await box.flush();
}

Future<void> remove(String path) async {
  final box = await _box();
  await box.delete(path);
  await box.flush();
}
