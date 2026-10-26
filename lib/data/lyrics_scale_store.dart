import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How big the words are on the stage of the wide layout, as a factor on the
/// size the stage picks from its height.
///
/// Kept per device like the music service: it is a property of the room the
/// device plays in - the distance to the wall, the projector it is plugged
/// into - not of a game, so it outlives every one of them.
class LyricsScaleStore {
  static const String _key = 'lyrics.scale';

  /// The stage's own size, unscaled.
  static const double normal = 1;

  /// Far enough either way to be worth a button, close enough that the words
  /// still fit the box at both ends.
  static const double min = 0.6;
  static const double max = 2.4;

  /// One press of smaller or bigger. A factor rather than a step, so a press
  /// does the same amount of work at either end of the range.
  static const double step = 1.2;

  /// [scale] a press smaller or bigger, kept inside the range.
  static double stepped(double scale, {required bool bigger}) =>
      (bigger ? scale * step : scale / step).clamp(min, max);

  static Future<double> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_key);
      return saved == null ? normal : saved.clamp(min, max);
    } on Object catch (error) {
      debugPrint('Lyrics scale not readable: $error');
      return normal;
    }
  }

  static Future<void> save(double scale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_key, scale);
    } on Object catch (error) {
      debugPrint('Could not save the lyrics scale: $error');
    }
  }
}
