import 'dart:io';

import 'package:hive/hive.dart';

import '../models/workout_session.dart';
import 'hive_service.dart';

String snapshotPath(String kind, String ownerKey) {
  final root =
      File(Hive.box<WorkoutSession>(HiveService.sessionsBox).path!).parent.path;
  return '$root/training-$kind-$ownerKey.json';
}

Future<bool> exists(String path) => File(path).exists();
Future<String> read(String path) => File(path).readAsString();
Future<void> write(String path, String value) async {
  final pending = File('$path.pending');
  await pending.writeAsString(value, flush: true);
  await pending.rename(path);
}

Future<void> remove(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}
