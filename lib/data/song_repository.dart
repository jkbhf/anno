import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/song_category.dart';

/// Order of the categories on the selection screen.
///
/// To add a category: drop a JSON file into `assets/songs/` and list it here -
/// `assets/songs/` is registered as a folder in the pubspec.
const List<String> categoryAssets = [
  'assets/songs/esc.json',
  'assets/songs/german_songs.json',
  'assets/songs/international_hits.json',
  'assets/songs/kpop.json',
];

/// Loads the song catalogs from the JSON assets.
class SongRepository {
  static Future<List<SongCategory>> loadAll({AssetBundle? bundle}) async {
    final source = bundle ?? rootBundle;
    final categories = <SongCategory>[];
    for (final asset in categoryAssets) {
      final raw = await source.loadString(asset);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      categories.add(SongCategory.fromJson(json));
    }
    return categories;
  }
}
