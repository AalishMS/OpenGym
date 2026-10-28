import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/split_provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../services/sync_service.dart';
import '../services/training_block_migration.dart';
import '../services/training_block_restore.dart';
import 'data_preparation_failure.dart';

/// A failed multi-box write cannot expose a partially replaced logger, even
/// when the original confirmation dialog is dismissed.
class TrainingDataGate extends StatelessWidget {
  final Widget child;
  const TrainingDataGate({required this.child, super.key});

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TrainingPreparationException?>(
        valueListenable: TrainingBlockRestore.recoveryFailure,
        builder: (context, error, _) {
          if (error == null) return child;
          final owner = TrainingBlockRestore.recoveryOwnerId;
          return DataPreparationFailure(
            onExport: () => exportTrainingSafetyCopy(error.safetySnapshotPath),
            onRetry: () async {
              await SyncService.instance.runExclusiveLocalMutation(() async {
                await TrainingBlockRestore().recover(ownerId: owner);
                await TrainingBlockMigration().normalizeUnderGate(
                  ownerId: owner,
                );
              });
              if (!context.mounted) return;
              await context.read<SettingsProvider>().reload();
              if (!context.mounted) return;
              context.read<SplitProvider>().loadSplits();
              context.read<WorkoutPlanProvider>().loadPlans();
              context.read<WorkoutSessionProvider>().loadSessions();
            },
          );
        },
      );
}
