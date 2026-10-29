import 'training_recovery_snapshots_io.dart'
    if (dart.library.js_interop) 'training_recovery_snapshots_web.dart'
    as storage;

/// Owner-scoped recovery artifacts. Native files and browser IndexedDB keep
/// the same snapshot-before-journal ordering without storing graphs in settings.
abstract final class TrainingRecoverySnapshots {
  static String path(String kind, String ownerKey) =>
      storage.snapshotPath(kind, ownerKey);
  static Future<bool> exists(String path) => storage.exists(path);
  static Future<String> read(String path) => storage.read(path);
  static Future<void> write(String path, String value) =>
      storage.write(path, value);
  static Future<void> remove(String path) => storage.remove(path);
}
