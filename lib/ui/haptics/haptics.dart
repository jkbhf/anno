import 'haptic_kind.dart';
import 'haptics_native.dart' if (dart.library.js_interop) 'haptics_web.dart';

/// Short physical feedback for the moments where the screen alone is not
/// enough: the phone travels around the group and nobody is looking at it
/// closely while tapping.
abstract final class Haptics {
  static void tick() => playHaptic(HapticKind.tick);

  static void point() => playHaptic(HapticKind.point);

  static void undo() => playHaptic(HapticKind.undo);

  static void reveal() => playHaptic(HapticKind.reveal);
}
