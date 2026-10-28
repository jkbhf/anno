import 'package:anno/data/csv_deck.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads a playlist export as it stands', () {
    const csv =
        '﻿Track URI,Track Name,Album Name,Artist Name(s),Release Date\n'
        'spotify:track:0vf2eBw2inhl8y61cYQMv2,"Devil, Town","Cavetown","A;B",2015-11-09\n'
        'spotify:track:2gvmxusSOe3vNjNDjQWaso,"Say ""Hi""",x,C,2006\n'
        ',No year,x,D,\n';
    final deck = CsvDeck.parse(csv, name: 'Daily Chill');
    expect(deck.id, 'import_daily_chill');
    expect(deck.imported, isTrue);
    expect(deck.songs, hasLength(2));
    expect(deck.songs.first.title, 'Devil, Town');
    expect(deck.songs.first.artist, 'A, B');
    expect(deck.songs.first.year, 2015);
    expect(deck.songs.first.spotifyTrackId, '0vf2eBw2inhl8y61cYQMv2');
    expect(deck.songs.last.title, 'Say "Hi"');
  });

  test('names the deck after the file', () {
    expect(CsvDeck.nameOf('daily_chill (1).csv'), 'Daily Chill');
  });

  test('rejects a file that is not an export', () {
    expect(() => CsvDeck.parse('a,b\n1,2', name: 'x'), throwsFormatException);
  });
}
