import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// `document.fullscreenEnabled` - false in an iframe without the permission,
/// and on an iPhone before 16.4, where the element API does not exist.
bool fullscreenSupported() {
  try {
    final enabled = (web.document as JSObject).getProperty<JSBoolean?>(
      'fullscreenEnabled'.toJS,
    );
    if (enabled == null || !enabled.toDart) return false;
    final element = web.document.documentElement as JSObject?;
    return element?.hasProperty('requestFullscreen'.toJS).toDart ?? false;
  } on Object {
    return false;
  }
}

bool fullscreenIsOn() {
  try {
    return (web.document as JSObject).getProperty<JSAny?>(
          'fullscreenElement'.toJS,
        ) !=
        null;
  } on Object {
    return false;
  }
}

/// Fullscreen for the whole page, not for one element: the game is the page.
///
/// A refusal is the normal case rather than an error - the browser only grants
/// it to a gesture, and some refuse it in an iframe whatever the flag says. The
/// game then runs on as it did, with the bar still there.
Future<void> toggleFullscreen() async {
  try {
    if (fullscreenIsOn()) {
      await (web.document as JSObject)
          .callMethod<JSPromise<JSAny?>>('exitFullscreen'.toJS)
          .toDart;
      return;
    }
    final element = web.document.documentElement as JSObject?;
    if (element == null) return;
    await element
        .callMethod<JSPromise<JSAny?>>('requestFullscreen'.toJS)
        .toDart;
  } on Object {
    // Refused. Nothing in the game depends on it.
  }
}
