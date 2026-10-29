import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/split_provider.dart';
import '../providers/workout_plan_provider.dart';
import '../screens/history_screen.dart';
import '../screens/workout_screen.dart';
import '../services/hive_service.dart';
import '../services/supabase_service.dart';
import 'app_navigation_observer.dart';
import 'workout_destination.dart';

/// Shares modal/autosave deferral and account invalidation across entry points.
Future<void> openWorkoutDestination(
  BuildContext context,
  WorkoutDestination destination, {
  bool requestLogConfirmation = false,
  bool requireIncomplete = false,
}) async {
  final generation = SupabaseService.accountGeneration;
  final owner = SupabaseService.currentUserId;
  Future<void> deliver(bool confirm) async {
    if (!context.mounted || generation != SupabaseService.accountGeneration) {
      return;
    }
    final resolved = destination.resolve(ownerId: owner);
    if (resolved == null ||
        requireIncomplete && resolved.session?.isCompleted != false) {
      return;
    }
    final splitProvider = context.read<SplitProvider?>();
    final splitId = resolved.plan?.splitId;
    if (splitId != null &&
        splitProvider != null &&
        splitProvider.activeSplitId != splitId) {
      try {
        await splitProvider.setActiveSplit(splitId);
      } catch (_) {
        // An unavailable preference write must not strand an offline timer.
      }
      if (!context.mounted || generation != SupabaseService.accountGeneration) {
        return;
      }
    }
    // Re-fetch after the asynchronous preference write as well.
    final delivered = destination.resolve(ownerId: owner);
    if (delivered == null ||
        requireIncomplete && delivered.session?.isCompleted != false) {
      return;
    }
    context.read<WorkoutPlanProvider?>()?.loadPlans();
    final plan = delivered.plan;
    final session = delivered.session;
    if (session?.isCompleted == true ||
        plan == null ||
        delivered.week == null) {
      if (session == null) return;
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutDetailsScreen(sessionIdentity: session.id!),
          ),
        ),
      );
    } else {
      final plans = HiveService.getPlans(splitId: plan.splitId);
      final index = plans.indexWhere((p) => p.id == plan.id);
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder:
                (_) => WorkoutScreen(
                  plan: plan,
                  planIndex: index < 0 ? 0 : index,
                  destination: destination,
                  showLogConfirmationOnOpen: confirm,
                ),
          ),
        ),
      );
    }
    await WidgetsBinding.instance.endOfFrame;
  }

  final observer = AppNavigationObserver.maybeOf(context);
  if (observer == null) {
    await deliver(requestLogConfirmation);
  } else {
    await observer.openWorkout(
      destination.navigationKey,
      requestLogConfirmation: requestLogConfirmation,
      openIfMissing: deliver,
      isStillValid: () {
        if (!context.mounted ||
            generation != SupabaseService.accountGeneration) {
          return false;
        }
        final resolved = destination.resolve(ownerId: owner);
        return resolved != null &&
            (!requireIncomplete || resolved.session?.isCompleted == false);
      },
    );
  }
}
