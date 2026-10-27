import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether this phone has been seen to fail Spotify's Web Playback SDK on its
/// very first track, kept per device.
///
/// Spotify does not officially support the SDK in a mobile browser, but
/// plenty of phones run it fine and it is worth trying there too - it plays
/// silently inside the tab, no app opens and no title is ever shown. Where it
/// genuinely does not work, that shows up as a `playback_error` on the first
/// song a phone ever tries (`_SdkThenConnectSession` in
/// `spotify_session_web.dart`), and once that has happened there is no reason
/// to pay for the same failed attempt every evening - this remembers it so
/// the phone goes straight to Spotify Connect from then on.
///
/// Read synchronously ([sdkFailed]) because `createSpotifySession` decides
/// which player to build before there is anything to await, and filled by
/// [preload] at startup like the other per-device choices.
class SpotifySdkStore {
  static const String _key = 'spotify.sdk.failed';

  static bool _failed = false;

  static bool get sdkFailed => _failed;

  /// Reads the saved state into memory. Awaited once, at startup.
  static Future<void> preload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _failed = prefs.getBool(_key) ?? false;
    } on Object catch (error) {
      debugPrint('Spotify SDK state not readable: $error');
    }
  }

  static Future<void> markFailed() async {
    _failed = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } on Object catch (error) {
      debugPrint('Could not save the Spotify SDK state: $error');
    }
  }
}
