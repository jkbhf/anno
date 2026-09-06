import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'haptic_kind.dart';

/// Flutter's [HapticFeedback] does nothing on the web, so this goes straight to
/// `navigator.vibrate`.
///
/// Chrome on Android runs it, desktop browsers and iOS Safari do not implement
/// it at all - there the call is simply skipped.
void playHaptic(HapticKind kind) {
  final milliseconds = switch (kind) {
    HapticKind.tick => 12,
    HapticKind.point => 18,
    HapticKind.undo => 45,
    HapticKind.reveal => 30,
  };

  try {
    final navigator = globalContext.getProperty<JSObject?>('navigator'.toJS);
    if (navigator == null || !navigator.has('vibrate')) return;
    navigator.callMethod<JSBoolean>('vibrate'.toJS, milliseconds.toJS);
  } on Object {
    // A buzz is a nicety. A browser that refuses must not break the round.
  }
}
