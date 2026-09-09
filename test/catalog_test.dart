// Checks the shipped JSON files: a typo in them would otherwise only surface
// when the app starts.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anno/data/song_repository.dart';
import 'package:anno/models/song.dart';
import 'package:anno/models/song_category.dart';

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

  group('yearSpan', () {
    SongCategory build(List<int> years) => SongCategory(
      id: 'x',
      name: 'X',
      description: '',
      songs: [
        for (final year in years) Song(year: year, title: 't', artist: 'a'),
      ],
    );

    test('reads off the first and last year, not the song order', () {
      expect(build([1987, 1950, 2026, 1999]).yearSpan, equals('1950-2026'));
    });

    test('a single year is not written as a range', () {
      expect(build([1974, 1974]).yearSpan, equals('1974'));
    });

    test('an empty deck has no span', () {
      expect(build([]).yearSpan, isNull);
    });
  });
}
