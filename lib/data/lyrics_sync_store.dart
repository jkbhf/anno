import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How far the words run ahead of the song, on top of the small head start
/// every karaoke text has.
///
/// This is the cast: screen mirroring encodes, sends and decodes the picture,
/// which takes 150 to 400 milliseconds over Miracast or Smart View and up to
/// a second over a Chromecast, while the sound comes straight out of the
/// laptop. The words have to leave that much earlier to arrive on time.
///
/// Kept per device like the lyrics scale and the column width: it belongs to
/// the room and its chain of equipment, not to a game. A cable needs 0, so
/// the dialog offers that as one press.
class LyricsSyncStore {
  static const String _key = 'lyrics.sync';

  static const int none = 0;

  /// A usual cast, offered as a preset beside the cable's zero.
  static const int casting = 300;

  /// Below zero for a picture that somehow arrives first, far enough up for
  /// the slowest mirroring there is - a Chromecast over a busy network, or a
  /// television that adds its own processing on top.
  ///
  /// Both ends were tighter (-500 and 2000) and both were reached in a real
  /// room, so there is no point defending them.
  static const int min = -1000;
  static const int max = 3000;

  /// What one press of less or more moves.
  static const int step = 100;

  static int clamp(int ms) => ms.clamp(min, max);

  static Future<int> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_key);
      return saved == null ? none : clamp(saved);
    } on Object catch (error) {
      debugPrint('Lyrics sync not readable: $error');
      return none;
    }
  }

  static Future<void> save(int ms) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, ms);
    } on Object catch (error) {
      debugPrint('Could not save the lyrics sync: $error');
    }
  }
}
