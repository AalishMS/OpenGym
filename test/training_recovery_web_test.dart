@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/auth/data_preparation_failure.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/services/training_block_restore.dart';
import 'package:gymapp/services/training_recovery_snapshots.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await HiveService.init();
    await HiveService.clearAllPlans();
    await HiveService.clearAllSessions();
    await HiveService.clearSplitData();
    await HiveService.clearTrainingData();
    TrainingBlockRestore.recoveryFailure.value = null;
    await HiveService.putSplitRaw(
      Split(id: 's', name: 'Training', createdAt: DateTime(2026)),
    );
  });
  tearDown(() async {
    await TrainingBlockRestore().removeOwnerRecovery(null);
    await Hive.close();
  });

  test(
    'browser preparation retains an exportable safety copy across reopen',
    () async {
      expect(Hive.box<WorkoutSession>(HiveService.sessionsBox).path, isNull);
      await TrainingBlockMigration().normalize(ownerId: null);
      final path = TrainingBlockMigration().snapshotPath(null);
      expect(HiveService.getAllTrainingWeeksRaw(), hasLength(1));
      await Hive.close();
      await HiveService.init();
      final file = await trainingSafetyCopyFile(path);
      final payload = jsonDecode(await file.readAsString()) as Map;
      expect(payload['splits'].single['name'], 'Training');
      expect(file.mimeType, 'application/json');
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(HiveService.getAllTrainingWeeksRaw(), hasLength(1));
    },
  );

  test(
    'browser replacement resumes the fixed graph after interruption and reopen',
    () async {
      await TrainingBlockMigration().normalize(ownerId: null);
      final original = HiveService.readTrainingGraph(ownerId: null);
      final block = original.blocks.single;
      final desired = original.copyWith(
        blocks: [block.copyWith(name: 'Recovered')],
        weeks: [
          ...original.weeks,
          TrainingWeek(
            id: 'week-two',
            splitId: 's',
            blockId: block.id,
            number: 2,
            createdAt: DateTime(2026),
          ),
        ],
      );
      await expectLater(
        TrainingBlockRestore(
          onPhase: (phase) async {
            if (phase == 'parents') throw StateError('interrupted');
          },
        ).replace(graph: desired, stampRecords: false),
        throwsStateError,
      );
      final path = TrainingBlockRestore().snapshotPath(null);
      await Hive.close();
      await HiveService.init();
      await TrainingBlockRestore().recover(ownerId: null);
      expect(HiveService.getAllTrainingBlocksRaw().single.name, 'Recovered');
      expect(
        HiveService.getAllTrainingWeeksRaw().map((w) => w.number).toSet(),
        {1, 2},
      );
      expect(
        () => HiveService.readTrainingGraph(ownerId: null).validate(),
        returnsNormally,
      );
      final saved =
          jsonDecode(await (await trainingSafetyCopyFile(path)).readAsString())
              as Map;
      expect(saved['original']['blocks'].single['name'], 'Block 1');
      expect(saved['desired']['blocks'].single['name'], 'Recovered');
      expect(TrainingBlockRestore.recoveryFailure.value, isNull);
    },
  );

  test(
    'browser rollback restores the safety graph after a caught installer failure',
    () async {
      await TrainingBlockMigration().normalize(ownerId: null);
      final original = HiveService.readTrainingGraph(ownerId: null);
      final desired = original.copyWith(
        blocks: [original.blocks.single.copyWith(name: 'Edited')],
      );
      final restore = TrainingBlockRestore(
        onPhase: (phase) async {
          if (phase == 'parents') throw StateError('disk-like failure');
        },
      );
      await expectLater(
        restore.replace(graph: desired, stampRecords: false),
        throwsStateError,
      );
      await restore.rollbackUnderGate(null);
      expect(HiveService.getAllTrainingBlocksRaw().single.name, 'Block 1');
      expect(
        () => HiveService.readTrainingGraph(ownerId: null).validate(),
        returnsNormally,
      );
    },
  );

  test(
    'browser owner cleanup removes only that owners recovery artifacts',
    () async {
      final old = TrainingBlockMigration().snapshotPath('old-owner');
      final other = TrainingBlockMigration().snapshotPath('other-owner');
      await TrainingRecoverySnapshots.write(old, '{"ownerId":"old-owner"}');
      await TrainingRecoverySnapshots.write(other, '{"ownerId":"other-owner"}');
      await TrainingBlockRestore().removeOwnerRecovery('old-owner');
      expect(await TrainingRecoverySnapshots.exists(old), isFalse);
      expect(
        jsonDecode(await TrainingRecoverySnapshots.read(other))['ownerId'],
        'other-owner',
      );
      await TrainingBlockRestore().removeOwnerRecovery('other-owner');
    },
  );
}
