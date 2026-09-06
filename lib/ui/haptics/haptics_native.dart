import 'package:flutter/services.dart';

import 'haptic_kind.dart';

void playHaptic(HapticKind kind) {
  switch (kind) {
    case HapticKind.tick:
      HapticFeedback.selectionClick();
    case HapticKind.point:
      HapticFeedback.lightImpact();
    case HapticKind.undo:
      HapticFeedback.mediumImpact();
    case HapticKind.reveal:
      HapticFeedback.mediumImpact();
  }
}
