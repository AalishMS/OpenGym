import 'package:flutter/widgets.dart';

/// The app's motion vocabulary: a few durations, curves and distances that
/// every animation shares, so new motion doesn't invent its own timing.
///
/// Motion has four jobs: continuity (where something came from or went),
/// feedback (a touch acknowledged), change (a value that changed in place)
/// and arrival (content appearing for the first time). Reach first for the
/// primitives in `lib/widgets/motion/`, which already apply these values and
/// reduced motion; use the tokens directly only for motion they don't cover.
/// DESIGN.md's Motion section has the rules.
abstract final class AppMotion {
  /// A small state flip: a chevron turning, a colour or label settling, a
  /// card giving under the finger, one piece of content swapped for another.
  static const Duration quick = Duration(milliseconds: 150);

  /// A region opening or closing, a track or menu moving, a dialog arriving.
  static const Duration standard = Duration(milliseconds: 220);

  /// Something arriving on screen, a sheet rising, or a scroll the reader
  /// should follow.
  static const Duration enter = Duration(milliseconds: 280);

  /// A large move the eye follows across much of the screen: a chart's bars
  /// growing to a new week, an intro page trading places. Not for sheets or
  /// dialogs, which have their own timing (`showAppSheet`, `showAppDialog`).
  static const Duration long = Duration(milliseconds: 400);

  /// The gap between one arrival and the next when a few arrive together.
  /// Use it on a first appearance only, and for a handful of steps at most
  /// (`Entrance.index`), so the last item is never kept waiting.
  static const Duration stagger = Duration(milliseconds: 40);

  /// How long work may run before a progress indicator shows. A save or a
  /// sign-in check that finishes sooner shows none: a spinner or a progress
  /// line that appears and vanishes at once only flickers, and shoves the
  /// page if it takes room.
  static const Duration patience = Duration(milliseconds: 300);

  /// Motion into place: arrivals, and anything settling at a new value.
  static const Curve curve = Curves.easeOutCubic;

  /// Something already on screen travelling to another place on screen: a
  /// page turning, a spotlight moving between targets, a card sliding to a
  /// new slot, a title flying into a header. It starts from rest and comes to
  /// rest, so it neither lurches off nor brakes hard; an arrival, which comes
  /// from nowhere, settles on [curve] instead.
  static const Curve move = Curves.easeInOutCubic;

  /// Motion out of the way. Pass it as the *reverse* curve (`reverseCurve`,
  /// `switchOutCurve`) of the animation that brought the thing in: Flutter
  /// evaluates a reverse curve against the same 0–1 value, so the leaving
  /// thing gives way at once and is mostly gone in the first half of its
  /// time. That is why a departure reads shorter than its arrival.
  static const Curve exit = Curves.easeInCubic;

  /// How far an arriving thing rises into place (`Entrance`).
  static const double lift = 8;

  /// How far a page or panel travels sideways when it trades places with
  /// another (`PageSwitcher`: the exercise picker, Stats' views, the preset
  /// browser).
  static const double shift = 24;

  /// How far a page travels sideways when a swipe trades it for another, for
  /// a page [width] wide: a quarter of it, kept between 3 and 6 × [shift].
  /// The workout's plan switch is the case it is for. It follows a finger
  /// that has just carried the page a long way, so a [shift] would read as no
  /// move at all, while a whole width would make the eye chase it.
  static double swipeShift(double width) =>
      (width / 4).clamp(shift * 3, shift * 6);

  /// How small an object gets when it moves in scale: a card giving under the
  /// finger (`PressScale`), a dialog arriving. Scale is a hint, never a zoom.
  static const double scale = 0.97;

  /// A settle that follows a gesture: content that tracked the finger springs
  /// back to rest, carrying the release velocity, without overshoot. Drive it
  /// with `controller.animateWith(SpringSimulation(AppMotion.settle, from, to,
  /// velocity))`; from a short pull it is within a pixel of rest in about
  /// [standard]. The workout's plan swipe is the case it is for: a log let go
  /// short of a switch springs back on it, and one that switches carries on
  /// out on it at the hand's speed. Under reduced motion, jump to rest.
  static final SpringDescription settle = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 700,
  );

  /// [duration], or no time at all when the platform asks for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
