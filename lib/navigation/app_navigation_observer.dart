import 'dart:async';

import 'package:flutter/material.dart';

/// A mounted workout, identified by the session actually being displayed.
abstract interface class WorkoutNavigationTarget {
  bool displaysSession(String sessionId);
  bool get canHandleNotification;
  Future<bool> handleNotification({required bool requestLogConfirmation});
}

/// Tracks this account's stack and returns to workouts through normal leave
/// flows. A cancelled prompt or a busy modal never causes a duplicate push.
class AppNavigationObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];
  final Map<Route<dynamic>, AppRouteParticipant> _participants = {};
  String? _pendingSessionId;
  bool _pendingLogConfirmation = false;
  Future<void> Function(bool)? _pendingOpen;
  Route<dynamic>? _blockedLeaveRoute;
  bool _returning = false;
  bool _deliveryScheduled = false;

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

  /// Both reuse and new pushes wait behind modal input, confirmations and busy
  /// operations. The callback receives the merged Stop request from all intents.
  Future<void> openWorkout(
    String sessionId, {
    required bool requestLogConfirmation,
    required Future<void> Function(bool requestLogConfirmation) openIfMissing,
  }) async {
    _pendingLogConfirmation =
        requestLogConfirmation ||
        (_pendingSessionId == sessionId && _pendingLogConfirmation);
    _pendingSessionId = sessionId;
    _pendingOpen = openIfMissing;
    _blockedLeaveRoute = null;
    await _resumePending();
  }

  Future<void> _resumePending() async {
    final id = _pendingSessionId;
    if (id == null || _returning || _routes.isEmpty) return;
    // Cancel means stay here. Closing that prompt must not immediately ask
    // again; only a new intent or leaving the guarded route can retry.
    if (_blockedLeaveRoute != null && _routes.contains(_blockedLeaveRoute)) {
      return;
    }
    _blockedLeaveRoute = null;
    _returning = true;
    try {
      final targetRoute = _workoutRoute(id);
      while (_routes.isNotEmpty && _routes.last != targetRoute) {
        final top = _routes.last;
        // A dialog may contain unsaved input or be completing a write whose
        // success callback pops itself. Never push over it or cancel it.
        if (top is PopupRoute) return;
        final participant = _participants[top];
        if (participant != null) {
          await participant.leaveRoute();
        } else if (targetRoute == null) {
          break;
        } else {
          await navigator?.maybePop();
        }
        // A save/discard was cancelled, a keypad consumed Back, or a busy
        // modal vetoed it. Wait until the user actually returns to the workout.
        if (_pendingSessionId != id || _routes.isEmpty) {
          return;
        }
        // Do not dismiss a new prompt that appeared during an asynchronous save.
        if (_routes.contains(top)) {
          _blockedLeaveRoute = top;
          return;
        }
      }
      if (_pendingSessionId != id || _routes.isEmpty) return;
      if (targetRoute == null) {
        final open = _pendingOpen;
        final confirm = _pendingLogConfirmation;
        _clearPending();
        await open?.call(confirm);
      } else {
        await _deliverPending();
      }
    } finally {
      _returning = false;
      if (_pendingSessionId != null && _pendingSessionId != id) {
        _scheduleDelivery();
      }
    }
  }

  void _scheduleDelivery() {
    if (_pendingSessionId == null || _deliveryScheduled) return;
    _deliveryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deliveryScheduled = false;
      if (!_returning) {
        unawaited(
          _resumePending().catchError((Object error) {
            debugPrint('Could not resume notification navigation: $error');
          }),
        );
      }
    });
  }

  Future<void> _deliverPending() async {
    final id = _pendingSessionId;
    if (id == null || _routes.isEmpty) return;
    final target = _participants[_routes.last]?.workoutTarget;
    if (target == null ||
        !target.displaysSession(id) ||
        !target.canHandleNotification) {
      return;
    }
    final confirm = _pendingLogConfirmation;
    final accepted = await target.handleNotification(
      requestLogConfirmation: confirm,
    );
    if (accepted && _pendingSessionId == id) _clearPending();
  }

  void _clearPending() {
    _pendingSessionId = null;
    _pendingLogConfirmation = false;
    _pendingOpen = null;
    _blockedLeaveRoute = null;
  }
}

/// Registers the same asynchronous leave flow used by a screen's Back button.
/// Optional outside the real app (for example, isolated widget tests).
mixin AppRouteParticipant<T extends StatefulWidget> on State<T> {
  AppNavigationObserver? _navigationObserver;
  ModalRoute<dynamic>? _navigationRoute;

  Future<void> leaveRoute();
  WorkoutNavigationTarget? get workoutTarget => null;

  /// A busy workout can become ready without any route being popped.
  void navigationStateChanged() => _navigationObserver?._scheduleDelivery();

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
      observer._scheduleDelivery();
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
