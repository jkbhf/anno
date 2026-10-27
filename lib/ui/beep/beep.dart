import 'beep_native.dart'
    if (dart.library.js_interop) 'beep_web.dart'
    as platform;

/// A short click out of the device's own speakers.
///
/// The one sound the game makes itself - everything else is Spotify's. It is
/// the reference for [showLyricsSyncDialog]: the click is heard the moment it
/// is played, while the picture beside it takes the long way through a cast,
/// and the difference between the two is what the dialog measures.
abstract final class Beep {
  /// Whether this build can make the sound at all. False on Android and iOS,
  /// where there is no Web Audio and no casting of a laptop screen either.
  static bool get isSupported => platform.beepSupported();

  /// Plays it. Must be called from a tap the first time: a browser does not
  /// let a page make a sound before it has been touched.
  static void play() => platform.playBeep();
}
