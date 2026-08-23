import 'package:flutter/painting.dart';

/// Corner radius scale (logical pixels).
///
/// One source of truth for how round the app is. Call sites use the *semantic*
/// aliases below ([card], [button], [chip], …) rather than the raw scale, so
/// retuning the app's roundness means editing the six scale constants here and
/// nothing else.
///
/// The scale is graduated by element size on purpose: the UI is dense (8–14px
/// type, 24–32px controls), and a single global radius would turn a 20×24 badge
/// into a blob while barely registering on a 148px card.
///
/// Reach for a token instead of a bare `BorderRadius.circular(...)` in new and
/// touched code — and never leave a full-perimeter box unrounded.
class AppRadius {
  AppRadius._();

  // --- scale ---

  /// Heatmap cells, chart bar caps.
  static const double xxs = 2;

  /// Badges, swatches, radio boxes — anything under ~24px.
  static const double xs = 4;

  /// Chips, tab pills, small controls.
  static const double sm = 6;

  /// Buttons, text fields, list rows.
  static const double md = 10;

  /// Cards, panels, dialogs.
  static const double lg = 14;

  /// Bottom sheets.
  static const double xl = 20;

  // --- semantic aliases: what call sites use ---

  /// Cards, panels, dialogs, bordered content boxes.
  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));

  /// Buttons and full-width tap targets.
  static const BorderRadius button = BorderRadius.all(Radius.circular(md));

  /// Text fields and other input decorations.
  static const BorderRadius field = button;

  /// Chips, tab pills, small selectables.
  static const BorderRadius chip = BorderRadius.all(Radius.circular(sm));

  /// Steppers, arrow buttons, ≤32px squares.
  static const BorderRadius control = chip;

  /// Index pills, PR flags, colour swatches, radio boxes.
  static const BorderRadius badge = BorderRadius.all(Radius.circular(xs));

  /// Heatmap cells, legend keys, drag handles.
  static const BorderRadius micro = BorderRadius.all(Radius.circular(xxs));

  /// Modal bottom sheet — top corners only.
  static const BorderRadius sheet =
      BorderRadius.vertical(top: Radius.circular(xl));

  /// A header region sitting at the top of an already-rounded card. Used for
  /// the tappable header of an expandable card, so its ink splash follows the
  /// card's top corners without rounding the bottom ones.
  static const BorderRadius cardTop =
      BorderRadius.vertical(top: Radius.circular(lg));

  /// The mirror of [cardTop] — a row sitting flush with the bottom of a card,
  /// such as an `+ ADD SET` footer, so its ink splash follows the card's bottom
  /// corners instead of squaring them off on press.
  static const BorderRadius cardBottom =
      BorderRadius.vertical(bottom: Radius.circular(lg));

  /// Left cap of a horizontally-joined segment group (steppers): outer corners
  /// round, shared inner edges square, so the segments read as one control.
  static const BorderRadius leftCap =
      BorderRadius.horizontal(left: Radius.circular(sm));

  /// Right cap of a horizontally-joined segment group. See [leftCap].
  static const BorderRadius rightCap =
      BorderRadius.horizontal(right: Radius.circular(sm));

  /// Top-only cap for a vertical bar chart rod, so the baseline stays flat.
  static const BorderRadius barCap =
      BorderRadius.vertical(top: Radius.circular(xxs));
}
