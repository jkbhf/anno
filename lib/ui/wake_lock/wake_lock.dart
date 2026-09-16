import 'wake_lock_native.dart'
    if (dart.library.js_interop) 'wake_lock_web.dart'
    as platform;

/// Keeps the screen on while a game runs.
///
/// A round played in the tab is exactly the stretch where nobody touches the
/// phone: the song runs, the room guesses, and after thirty seconds the screen
/// goes dark on the reveal button. A lock the browser does not grant costs
/// nothing - the screen then simply sleeps as before.
abstract final class WakeLock {
  /// Asks for the lock. Call again when the page comes back into view: the
  /// browser drops it whenever the tab is hidden.
  static Future<void> hold() => platform.holdWakeLock();

  static Future<void> release() => platform.releaseWakeLock();
}
