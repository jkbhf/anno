import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every song this device has played, for good.
///
/// `GameController` does not draw a song again while its year in its deck
/// still holds one nobody has heard here - not in the same game, not next
/// week. Only when a year is used up does it start over, and then its songs
/// leave this memory again.
///
/// Kept apart from [GameStore] like the roster: a saved game is cleared when
/// it ends, and this is worth most exactly then.
class PlayedSongsStore {
  /// The key of the memory that used to keep only the last 300 songs - kept,
  /// so what those evenings played is not heard again either.
  static const String _key = 'songs.recent';

  /// The played keys, as `GameController.playedKey`s.
  static Future<Set<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const {};
      return {
        for (final entry in jsonDecode(raw) as List)
          if (entry is String) entry,
      };
    } on Object catch (error) {
      debugPrint('Played songs not readable: $error');
      return const {};
    }
  }

  /// Replaces the memory with [keys].
  static Future<void> save(Set<String> keys) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode([...keys]));
    } on Object catch (error) {
      debugPrint('Could not save the played songs: $error');
    }
  }
}
