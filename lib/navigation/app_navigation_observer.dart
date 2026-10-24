import 'dart:async';

import 'package:flutter/material.dart';

/// A mounted workout, identified by the session actually being displayed.
abstract interface class WorkoutNavigationTarget {
  bool displaysSession(String sessionId);
  Future<void> handleNotification({required bool requestLogConfirmation});
}

/// Tracks this account's stack and returns to workouts through normal leave
/// flows. A cancelled prompt or a busy modal never causes a duplicate push.
class AppNavigationObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];
  final Map<Route<dynamic>, AppRouteParticipant> _participants = {};
  String? _pendingSessionId;
  bool _pendingLogConfirmation = false;
  bool _returning = false;

  static AppNavigationObserver? maybeOf(BuildContext context) {
    for (final observer in Navigator.of(context).widget.observers) {
      if (observer is AppNavigationObserver) return observer;
    }
    return null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _scheduleDelivery();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _scheduleDelivery();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _scheduleDelivery();
  }

  Route<dynamic>? _workoutRoute(String sessionId) {
    for (final route in _routes.reversed) {
      if (_participants[route]?.workoutTarget?.displaysSession(sessionId) ??
          false) {
        return route;
      }
    }
    return null;
  }

  /// True also means "already exists, but a leave guard kept us here".
  Future<bool> returnToWorkout(
    String sessionId, {
    required bool requestLogConfirmation,
  }) async {
    final targetRoute = _workoutRoute(sessionId);
    if (targetRoute == null) return false;
    _pendingLogConfirmation =
        requestLogConfirmation ||
        (_pendingSessionId == sessionId && _pendingLogConfirmation);
    _pendingSessionId = sessionId;
    if (_returning) return true;
    _returning = true;
    try {
      while (_routes.isNotEmpty && _routes.last != targetRoute) {
        final top = _routes.last;
        final participant = _participants[top];
        if (participant != null) {
          await participant.leaveRoute();
        } else {
          await navigator?.maybePop();
        }
        // A save/discard was cancelled, a keypad consumed Back, or a busy
        // modal vetoed it. Wait until the user actually returns to the workout.
        if (_routes.isEmpty || _routes.last == top) return true;
        // Do not dismiss a new prompt that appeared during an asynchronous save.
        if (_routes.contains(top)) return true;
      }
      await _deliverPending();
      return true;
    } finally {
      _returning = false;
    }
  }

  void _scheduleDelivery() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_returning) unawaited(_deliverPending());
    });
  }

  Future<void> _deliverPending() async {
    final id = _pendingSessionId;
    if (id == null || _routes.isEmpty) return;
    final target = _participants[_routes.last]?.workoutTarget;
    if (target == null || !target.displaysSession(id)) return;
    final confirm = _pendingLogConfirmation;
    _pendingSessionId = null;
    _pendingLogConfirmation = false;
    await target.handleNotification(requestLogConfirmation: confirm);
  }
}

/// Registers the same asynchronous leave flow used by a screen's Back button.
/// Optional outside the real app (for example, isolated widget tests).
mixin AppRouteParticipant<T extends StatefulWidget> on State<T> {
  AppNavigationObserver? _navigationObserver;
  ModalRoute<dynamic>? _navigationRoute;

  Future<void> leaveRoute();
  WorkoutNavigationTarget? get workoutTarget => null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = AppNavigationObserver.maybeOf(context);
    final route = ModalRoute.of(context);
    if (observer == _navigationObserver && route == _navigationRoute) return;
    _unregister();
    _navigationObserver = observer;
    _navigationRoute = route;
    if (observer != null && route != null) {
      observer._participants[route] = this;
    }
  }

  void _unregister() {
    final observer = _navigationObserver;
    final route = _navigationRoute;
    if (observer?._participants[route] == this) {
      observer?._participants.remove(route);
    }
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }
}
