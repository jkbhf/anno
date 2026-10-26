import 'fullscreen_native.dart'
    if (dart.library.js_interop) 'fullscreen_web.dart'
    as platform;

/// The browser's own chrome, out of the way.
///
/// The one thing the game cannot style and the one thing nobody wants on a
/// wall: the address bar. On a phone turned over it is worth more than that -
/// mobile browsers keep a bar at the top and a hairline at the bottom, which
/// is a tenth of a landscape screen the stage could have instead.
///
/// Nothing in the game depends on it. Where the browser refuses - an iframe
/// without the permission, a policy, iOS before 16.4 - [isSupported] is false
/// and the entry that offers it stays out of the menu.
abstract final class Fullscreen {
  /// Whether this build and this browser can do it at all. False on Android
  /// and iOS, where there is no browser chrome to hide.
  static bool get isSupported => platform.fullscreenSupported();

  /// Whether the page is in fullscreen right now. Read when the menu opens,
  /// so the entry says the thing it is about to do.
  static bool get isOn => platform.fullscreenIsOn();

  /// Asks for fullscreen, or leaves it. Must be called from a tap: a browser
  /// grants it to a user gesture and to nothing else.
  static Future<void> toggle() => platform.toggleFullscreen();
}
