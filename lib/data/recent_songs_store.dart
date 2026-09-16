import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The songs the last evenings played on this device.
///
/// `GameController` keeps a game from repeating itself, but that memory ends
/// with the game. Across evenings the draw would be plain random, and on the
/// narrow range of cards that actually gets played the same core songs come
/// back week after week. This is the longer memory: songs in here are drawn
/// less often, not never - see `GameController._freshAcrossEveningsWeight`.
///
/// Kept apart from [GameStore] like the roster: a saved game is cleared when
/// it ends, and this is worth most exactly then.
class RecentSongsStore {
  static const String _key = 'songs.recent';

  /// How many songs are remembered. An evening plays thirty to fifty rounds, so
  /// this reaches back about half a dozen evenings - long enough that a song
  /// is not heard again next week, short enough that a deck played often does
  /// not end up with nothing but "recent" songs, which would be the same as
  /// remembering nothing.
  static const int capacity = 300;

  /// The remembered keys, oldest first.
  static Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const [];
      return [
        for (final entry in jsonDecode(raw) as List)
          if (entry is String) entry,
      ];
    } on Object catch (error) {
      debugPrint('Recent songs not readable: $error');
      return const [];
    }
  }

  /// Remembers [key] as the most recent song.
  static Future<void> add(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = remember(await load(), key);
      await prefs.setString(_key, jsonEncode(keys));
    } on Object catch (error) {
      debugPrint('Could not save the recent songs: $error');
    }
  }

  /// [keys] with [key] moved to the end, cut down to [capacity].
  @visibleForTesting
  static List<String> remember(List<String> keys, String key) {
    final next = [
      for (final existing in keys)
        if (existing != key) existing,
      key,
    ];
    return next.length <= capacity
        ? next
        : next.sublist(next.length - capacity);
  }
}
