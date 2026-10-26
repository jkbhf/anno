import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the scoreboard is on the screen at all, set from the game's menu.
///
/// Kept per device like the music service and the lyrics scale: a group that
/// plays without counting plays that way every evening, not for one game.
///
/// Hidden, there is nothing to tap, so no points are handed out and the game
/// does not reach its target - which is the point of the option, not a side
/// effect of it. The scores a game already has are kept and come back with it.
class ShowScoresStore {
  static const String _key = 'scores.shown';

  static Future<bool> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? true;
    } on Object catch (error) {
      debugPrint('Score setting not readable: $error');
      return true;
    }
  }

  static Future<void> save({required bool shown}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, shown);
    } on Object catch (error) {
      debugPrint('Could not save the score setting: $error');
    }
  }
}
