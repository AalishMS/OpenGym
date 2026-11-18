import 'package:flutter/widgets.dart';

/// The app's motion vocabulary: a few durations and curves that state changes,
/// reveals and entrances share, so new motion doesn't invent its own timing.
///
/// Older widgets still inline their own values (mostly these same ones); new
/// code should reach for these, and [of] for reduced motion.
abstract final class AppMotion {
  /// A small state flip: a chevron turning, a colour or label settling.
  static const Duration quick = Duration(milliseconds: 150);

  /// A region opening or closing, a track or menu moving.
  static const Duration standard = Duration(milliseconds: 220);

  /// Something arriving on screen, or a scroll the reader should follow.
  static const Duration enter = Duration(milliseconds: 280);

  /// Motion into place.
  static const Curve curve = Curves.easeOutCubic;

  /// Motion out of the way.
  static const Curve exit = Curves.easeInCubic;

  /// [duration], or no time at all when the platform asks for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
