import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/workout_session.dart';

enum WorkoutTimerNotificationState { running, paused }

class WorkoutTimerNotificationSnapshot {
  final String sessionId;
  final String? planId;
  final String? splitId;
  final String planName;
  final int weekNumber;
  final int accumulatedSeconds;
  final DateTime? runningSince;
  final WorkoutTimerNotificationState state;
  final int actionRevision;
  final bool pendingStop;

  const WorkoutTimerNotificationSnapshot({
    required this.sessionId,
    required this.planId,
    required this.splitId,
    required this.planName,
    required this.weekNumber,
    required this.accumulatedSeconds,
    required this.runningSince,
    required this.state,
    required this.actionRevision,
    required this.pendingStop,
  });

  bool get isRunning => state == WorkoutTimerNotificationState.running;

  int elapsedSeconds([DateTime? now]) {
    if (!isRunning || runningSince == null) return accumulatedSeconds;
    final delta = (now ?? DateTime.now()).difference(runningSince!).inSeconds;
    return accumulatedSeconds + (delta < 0 ? 0 : delta);
  }

  factory WorkoutTimerNotificationSnapshot.fromMap(Map<Object?, Object?> map) {
    final runningSinceMillis = map['runningSinceMillis'] as int?;
    return WorkoutTimerNotificationSnapshot(
      sessionId: map['sessionId']! as String,
      planId: map['planId'] as String?,
      splitId: map['splitId'] as String?,
      planName: map['planName']! as String,
      weekNumber: map['weekNumber']! as int,
      accumulatedSeconds: map['accumulatedSeconds']! as int,
      runningSince:
          runningSinceMillis == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(runningSinceMillis),
      state:
          map['running'] == true
              ? WorkoutTimerNotificationState.running
              : WorkoutTimerNotificationState.paused,
      actionRevision: map['actionRevision']! as int,
      pendingStop: map['pendingStop'] == true,
    );
  }
}

class WorkoutTimerNotificationEvent {
  final WorkoutTimerNotificationSnapshot snapshot;
  final bool openWorkout;
  final bool requestLogConfirmation;

  const WorkoutTimerNotificationEvent({
    required this.snapshot,
    required this.openWorkout,
    required this.requestLogConfirmation,
  });

  factory WorkoutTimerNotificationEvent.fromMap(Map<Object?, Object?> map) {
    final snapshot = WorkoutTimerNotificationSnapshot.fromMap(
      Map<Object?, Object?>.from(map['snapshot']! as Map),
    );
    return WorkoutTimerNotificationEvent(
      snapshot: snapshot,
      openWorkout: map['action'] == 'open' || map['action'] == 'stop',
      requestLogConfirmation: map['action'] == 'stop',
    );
  }
}

class WorkoutTimerNotificationService {
  WorkoutTimerNotificationService._() {
    if (_isAndroid) {
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  static final WorkoutTimerNotificationService instance =
      WorkoutTimerNotificationService._();

  static const MethodChannel _channel = MethodChannel(
    'com.aalishms.opengym/workout_timer_notification',
  );

  final StreamController<WorkoutTimerNotificationEvent> _events =
      StreamController<WorkoutTimerNotificationEvent>.broadcast();

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  Stream<WorkoutTimerNotificationEvent> get events => _events.stream;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'notificationIntent' || call.arguments is! Map) return;
    _events.add(
      WorkoutTimerNotificationEvent.fromMap(
        Map<Object?, Object?>.from(call.arguments as Map),
      ),
    );
  }

  Future<bool> requestPermission() async {
    if (!_isAndroid) return false;
    return await _channel.invokeMethod<bool>('requestPermission') ?? false;
  }

  Future<void> show(WorkoutSession session) async {
    if (!_isAndroid || session.id == null) return;
    await _channel.invokeMethod<void>('show', _arguments(session));
  }

  Future<void> pause(WorkoutSession session) async {
    if (!_isAndroid || session.id == null) return;
    await _channel.invokeMethod<void>('pause', _arguments(session));
  }

  Future<void> dismiss() async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('dismiss');
  }

  Future<void> acknowledgeStop() async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('acknowledgeStop');
  }

  Future<WorkoutTimerNotificationSnapshot?> snapshot() async {
    if (!_isAndroid) return null;
    final value = await _channel.invokeMethod<Map<Object?, Object?>>(
      'snapshot',
    );
    return value == null
        ? null
        : WorkoutTimerNotificationSnapshot.fromMap(value);
  }

  Future<WorkoutTimerNotificationEvent?> consumeIntent() async {
    if (!_isAndroid) return null;
    final value = await _channel.invokeMethod<Map<Object?, Object?>>(
      'consumeIntent',
    );
    return value == null ? null : WorkoutTimerNotificationEvent.fromMap(value);
  }

  Future<void> restore() async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('restore');
  }

  Map<String, Object?> _arguments(WorkoutSession session) => {
    'sessionId': session.id,
    'planId': session.planId,
    'splitId': session.splitId,
    'planName': session.planName,
    'weekNumber': session.weekNumber,
    'accumulatedSeconds': session.durationSeconds ?? 0,
    'runningSinceMillis': session.timerStartedAt?.millisecondsSinceEpoch,
    'running': session.isTimerRunning,
  };
}
