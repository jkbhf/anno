// Checks the shipped JSON files: a typo in them would otherwise only surface
// when the app starts.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anno/data/song_repository.dart';
import 'package:anno/models/song_category.dart';

List<SongCategory> _load() => [
  for (final asset in categoryAssets)
    SongCategory.fromJson(
      jsonDecode(File(asset).readAsStringSync()) as Map<String, dynamic>,
    ),
];

void main() {
  test('every category in categoryAssets exists and parses', () {
    for (final asset in categoryAssets) {
      final file = File(asset);
      expect(file.existsSync(), isTrue, reason: '$asset is missing');

      final category = SongCategory.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
      expect(category.id, isNotEmpty);
      expect(category.name, isNotEmpty);
      expect(
        asset.endsWith('${category.id}.json'),
        isTrue,
        reason: 'file name and id should match: $asset',
      );

      for (final song in category.songs) {
        expect(song.year, inInclusiveRange(1900, 2100), reason: '$song');
        final id = song.spotifyTrackId;
        if (id != null) {
          expect(
            RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(id),
            isTrue,
            reason: 'not a Spotify track id: $song ($id)',
          );
        }
      }
    }
  });

  test('at least one shipped deck can carry a game on its own', () {
    // Otherwise the selection screen has no startable combination at all.
    expect(canCarryGame(_load()), isTrue);
  });

  test('a companion deck holds songs and covers its years without a gap', () {
    // Its whole point is to step in for the years it has, so a hole in the
    // middle of the range is a curation slip, not a deliberate thin year.
    for (final category in _load().where((c) => c.needsCompanion)) {
      expect(category.isEmpty, isFalse, reason: '${category.id} is empty');

      final years = category.songs.map((s) => s.year).toSet().toList()..sort();
      for (var year = years.first; year <= years.last; year++) {
        expect(
          category.songsForYear(year),
          isNotEmpty,
          reason: '${category.id} has nothing for $year',
        );
      }
    }
  });

  test('every year has at least as much core as tail', () {
    // How many entries a year gets is a curation rule and lives in CLAUDE.md,
    // not here - a running year or a deliberately deep one would only fight a
    // test. The split is a different matter: the draw weight leans on tier 1
    // being the majority, so a year that is mostly tail quietly turns the
    // weighting upside down.
    for (final category in _load()) {
      final years = category.songs.map((s) => s.year).toSet();
      for (final year in years) {
        final songs = category.songsForYear(year);
        final core = songs.where((s) => s.tier == 1).length;
        expect(
          core,
          greaterThanOrEqualTo(songs.length - core),
          reason: '${category.id} $year: $core core of ${songs.length}',
        );
      }
    }
  });

  test('the bundled year database parses', () {
    final json =
        jsonDecode(File('assets/qr_years.json').readAsStringSync())
            as Map<String, dynamic>;
    final years = json['years'] as Map<String, dynamic>;

    expect(years, isNotEmpty);
    for (final entry in years.entries) {
      expect(entry.value, isA<int>(), reason: entry.key);
      expect(entry.key, equals(entry.key.toLowerCase()));
    }
  });
}
