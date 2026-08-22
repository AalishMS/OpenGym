import 'package:flutter/widgets.dart';

/// Layout breakpoints (logical pixels).
///
/// The app is phone-first. Above [medium] the shell switches from the bottom
/// navigation bar to a [NavigationRail]-style sidebar and exposes the desktop
/// dashboard; [expanded] caps the content width so lists don't stretch
/// edge-to-edge on ultra-wide monitors.
class Breakpoints {
  Breakpoints._();

  /// Phones in portrait.
  static const double compact = 600;

  /// Small tablets / narrow desktop windows — the sidebar appears here.
  static const double medium = 900;

  /// Large desktop — content is centred and capped at this width.
  static const double expanded = 1280;

  /// True when the viewport is wide enough for the desktop rail layout.
  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= medium;
}
