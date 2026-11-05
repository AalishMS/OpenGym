import 'package:flutter/services.dart';

/// Haptics named for what happened, so the same moment always feels the same.
///
/// The keypad keeps its own key clicks. The system's haptic setting still
/// decides whether any of these play.
class Haptics {
  Haptics._();

  /// The workout clock started.
  static void confirm() => HapticFeedback.mediumImpact();

  /// A set entered as a new record, or a workout logged.
  static void celebrate() => HapticFeedback.heavyImpact();
}
