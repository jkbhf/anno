import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player.dart';

/// An interrupted game.
class SavedGame {
  const SavedGame({
    required this.players,
    required this.categoryIds,
    required this.targetScore,
    this.played = const [],
  });

  final List<GamePlayer> players;
  final List<String> categoryIds;
  final int targetScore;

  /// The songs the game has played so far, as `GameController.playedKey`s.
  final List<String> played;
}

/// Keeps the running game on the device.
///
/// Every round sends the players off to Spotify and the app into the
/// background. If the system kills it there, all points would be gone without
/// this.
class GameStore {
  static const String _key = 'game.current';

  /// Null for no game, and for anything that does not read as one.
  ///
  /// Catches everything, not just exceptions: a stored value of the wrong
  /// shape fails a cast with a [TypeError], and this runs before the first
  /// frame - a save that throws here is a page that never starts.
  static Future<SavedGame?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      return decode(raw);
    } on Object catch (error) {
      debugPrint('Saved game not readable: $error');
      return null;
    }
  }

  /// The stored form back to a game. Throws on a value of the wrong shape.
  @visibleForTesting
  static SavedGame? decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final players = [
      for (final entry in json['players'] as List)
        GamePlayer.fromJson(entry as Map<String, dynamic>),
    ];
    if (players.isEmpty) return null;

    // `categoryId` is what a game saved before multiple decks were possible
    // looks like.
    final ids = json['categoryIds'];
    final categoryIds = ids is List
        ? [for (final id in ids) id as String]
        : [json['categoryId'] as String];
    if (categoryIds.isEmpty) return null;

    // Missing in a game saved before it was kept: that game simply starts its
    // years over.
    final played = json['played'];

    return SavedGame(
      players: players,
      categoryIds: categoryIds,
      targetScore: json['targetScore'] as int,
      played: played is List ? [for (final key in played) key as String] : [],
    );
  }

  @visibleForTesting
  static String encode(SavedGame game) => jsonEncode({
    'players': [for (final p in game.players) p.toJson()],
    'categoryIds': game.categoryIds,
    'targetScore': game.targetScore,
    'played': game.played,
  });

  static Future<void> save(SavedGame game) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, encode(game));
    } on Object catch (error) {
      debugPrint('Could not save the game: $error');
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } on Object catch (error) {
      debugPrint('Could not delete the game: $error');
    }
  }
}
