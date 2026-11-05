import 'package:flutter/widgets.dart';

/// Returns [controller] to the top, as a reselected tab does. Animates unless
/// the platform asks for reduced motion, and does nothing before it attaches.
void scrollToTop(BuildContext context, ScrollController controller) {
  if (!controller.hasClients) return;
  if (MediaQuery.disableAnimationsOf(context)) {
    controller.jumpTo(0);
    return;
  }
  controller.animateTo(
    0,
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeOutCubic,
  );
}
