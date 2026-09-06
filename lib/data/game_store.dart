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
  });

  final List<GamePlayer> players;
  final List<String> categoryIds;
  final int targetScore;
}

/// Keeps the running game on the device.
///
/// Every round sends the players off to Spotify and the app into the
/// background. If the system kills it there, all points would be gone without
/// this.
class GameStore {
  static const String _key = 'game.current';

  static Future<SavedGame?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
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

      return SavedGame(
        players: players,
        categoryIds: categoryIds,
        targetScore: json['targetScore'] as int,
      );
    } on Exception catch (error) {
      debugPrint('Saved game not readable: $error');
      return null;
    }
  }

  static Future<void> save(SavedGame game) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'players': [for (final p in game.players) p.toJson()],
          'categoryIds': game.categoryIds,
          'targetScore': game.targetScore,
        }),
      );
    } on Exception catch (error) {
      debugPrint('Could not save the game: $error');
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } on Exception catch (error) {
      debugPrint('Could not delete the game: $error');
    }
  }
}
