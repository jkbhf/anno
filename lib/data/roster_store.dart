import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The names of the last group that played.
///
/// Deliberately separate from [GameStore]: that one holds a round in progress
/// and is cleared the moment a game ends, which is exactly when this one is
/// worth keeping. It outlives the game so the next evening starts with the
/// same names already in the fields.
///
/// Names only - no scores. A new evening starts at nil.
class RosterStore {
  static const String _key = 'roster.names';

  static Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const [];
      return [
        for (final entry in jsonDecode(raw) as List)
          if (entry is String && entry.trim().isNotEmpty) entry.trim(),
      ];
    } on Exception catch (error) {
      debugPrint('Roster not readable: $error');
      return const [];
    }
  }

  static Future<void> save(List<String> names) async {
    if (names.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(names));
    } on Exception catch (error) {
      debugPrint('Could not save the roster: $error');
    }
  }
}
