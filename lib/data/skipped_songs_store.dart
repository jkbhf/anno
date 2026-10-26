import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every song this device swapped away because nobody in the room knew it.
///
/// `GameController` draws such a song like the long tail of its year from
/// then on. Kept for good and apart from [GameStore] for the same reason as
/// `PlayedSongsStore`: the room that did not know it is the same room next
/// week.
class SkippedSongsStore {
  static const String _key = 'songs.skipped';

  /// The skipped keys, as `Song.key`s.
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
      debugPrint('Skipped songs not readable: $error');
      return const {};
    }
  }

  /// Replaces the memory with [keys].
  static Future<void> save(Set<String> keys) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode([...keys]));
    } on Object catch (error) {
      debugPrint('Could not save the skipped songs: $error');
    }
  }
}
