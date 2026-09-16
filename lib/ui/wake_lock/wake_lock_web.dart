import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// The sentinel `navigator.wakeLock.request` hands back, or null.
JSObject? _sentinel;

/// `navigator.wakeLock.request('screen')`, the Screen Wake Lock API.
///
/// Chrome, Edge and Safari from 16.4 have it; Firefox only from 126. The
/// browser releases the lock on its own whenever the tab is hidden, so a held
/// sentinel says nothing once the page was away - it is asked for again rather
/// than trusted.
Future<void> holdWakeLock() async {
  try {
    final navigator = globalContext.getProperty<JSObject?>('navigator'.toJS);
    final wakeLock = navigator?.getProperty<JSObject?>('wakeLock'.toJS);
    if (wakeLock == null) return;
    if (_sentinel case final held?
        when !(held.getProperty<JSBoolean?>('released'.toJS)?.toDart ?? true)) {
      return;
    }
    final request = wakeLock.callMethod<JSPromise<JSObject>>(
      'request'.toJS,
      'screen'.toJS,
    );
    _sentinel = await request.toDart;
  } on Object {
    // Refused - a hidden tab, a battery saver, a policy. The screen sleeps as
    // it always did, and the game does not care.
  }
}

Future<void> releaseWakeLock() async {
  final held = _sentinel;
  _sentinel = null;
  if (held == null) return;
  try {
    await held.callMethod<JSPromise<JSAny?>>('release'.toJS).toDart;
  } on Object {
    // Already released by the browser.
  }
}
