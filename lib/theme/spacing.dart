/// Spacing scale (logical pixels).
///
/// These match the values already recurring across the app (2–32), so adopting
/// them is a drop-in replacement for magic numbers — reach for a token instead
/// of a bare `EdgeInsets`/`SizedBox` literal in new and touched code.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}
