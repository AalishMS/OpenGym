import 'package:flutter/widgets.dart';

import '../theme/motion.dart';

/// Returns [controller] to the top, as a reselected tab does. Animates unless
/// the platform asks for reduced motion, and does nothing without a
/// controller or before it attaches.
void scrollToTop(BuildContext context, ScrollController? controller) {
  if (controller == null || !controller.hasClients) return;
  if (MediaQuery.disableAnimationsOf(context)) {
    controller.jumpTo(0);
    return;
  }
  controller.animateTo(0, duration: AppMotion.enter, curve: AppMotion.curve);
}
