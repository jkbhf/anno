import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../models/song_category.dart';

/// The decks imported from a file, kept on this device only.
class ImportedDecksStore {
  static const String _key = 'decks.imported';

  static Future<List<SongCategory>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const [];
      return [
        for (final entry in jsonDecode(raw) as List)
          SongCategory.fromJson({
            ...(entry as Map<String, dynamic>),
            'imported': true,
          }),
      ];
    } on Object catch (error) {
      debugPrint('Imported decks not readable: $error');
      return const [];
    }
  }

  static Future<void> save(List<SongCategory> decks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode([
          for (final deck in decks)
            {
              'id': deck.id,
              'name': deck.name,
              'description': deck.description,
              'songs': [for (final song in deck.songs) _songJson(song)],
            },
        ]),
      );
    } on Object catch (error) {
      debugPrint('Could not save the imported decks: $error');
    }
  }

  static Map<String, Object> _songJson(Song song) => {
    'title': song.title,
    'artist': song.artist,
    'year': song.year,
    if (song.spotifyTrackId != null) 'spotifyTrackId': song.spotifyTrackId!,
  };
}
