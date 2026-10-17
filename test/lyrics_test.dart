import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anno/models/song.dart';
import 'package:anno/music/lyrics.dart';

void main() {
  test('an LRC text is read line by line, in time order', () {
    final lyrics = Lyrics.fromLrc(
      '[ar:ABBA]\n'
      '[00:12.5] My, my\n'
      '[00:15.20][01:30.20] Waterloo\n'
      '[00:20.123]\n',
    );

    expect(lyrics.isSynced, isTrue);
    expect(lyrics.lines.map((line) => line.text), [
      'My, my',
      'Waterloo',
      '',
      'Waterloo',
    ]);
    expect(
      lyrics.lines.first.time,
      const Duration(seconds: 12, milliseconds: 500),
    );
    expect(
      lyrics.lines[2].time,
      const Duration(seconds: 20, milliseconds: 123),
    );
  });

  test('the line at a position is the last one that has started', () {
    final lyrics = Lyrics.fromLrc('[00:10.00] A\n[00:20.00] B');

    expect(lyrics.lineAt(const Duration(seconds: 5)), -1);
    expect(lyrics.lineAt(const Duration(seconds: 10)), 0);
    expect(lyrics.lineAt(const Duration(seconds: 25)), 1);
  });

  test('a plain text is not synced', () {
    expect(Lyrics.plain('A\nB').isSynced, isFalse);
  });

  group('picking a search hit', () {
    const synced = '[00:01.00] timed';

    test('a synced text that fits the recording wins', () {
      final lyrics = LrclibLyrics.pick([
        {'duration': 162.0, 'plainLyrics': 'plain'},
        {'duration': 163.0, 'syncedLyrics': synced, 'plainLyrics': 'plain'},
      ], const Duration(seconds: 162));

      expect(lyrics!.isSynced, isTrue);
    });

    test('a synced text for another cut only lends its words', () {
      final lyrics = LrclibLyrics.pick([
        {'duration': 240.0, 'syncedLyrics': synced},
      ], const Duration(seconds: 162));

      expect(lyrics!.isSynced, isFalse);
      expect(lyrics.lines.single.text, 'timed');
    });

    test('without a known length any synced text is taken', () {
      final lyrics = LrclibLyrics.pick([
        {'duration': 240.0, 'syncedLyrics': synced},
      ], null);

      expect(lyrics!.isSynced, isTrue);
    });

    test('an instrumental is said, nothing is null', () {
      expect(
        LrclibLyrics.pick([
          {'instrumental': true},
        ], null)!.instrumental,
        isTrue,
      );
      expect(LrclibLyrics.pick([], null), isNull);
    });
  });

  group('LRCLIB', () {
    const song = Song(
      title: 'Über sieben Brücken',
      artist: 'Maffay',
      year: 1980,
    );

    http.Response hits(String words) => http.Response.bytes(
      utf8.encode(
        jsonEncode([
          {'plainLyrics': words},
        ]),
      ),
      200,
      headers: {'content-type': 'application/json'},
    );

    test('the words are read as UTF-8 though no charset is sent', () async {
      final source = LrclibLyrics(
        client: MockClient((_) async => hits('Über sieben Brücken')),
      );

      final lyrics = await source.find(song);

      expect(lyrics!.lines.single.text, 'Über sieben Brücken');
    });

    test('a throttled request is tried again by itself', () async {
      var calls = 0;
      final source = LrclibLyrics(
        retryDelay: Duration.zero,
        client: MockClient((_) async {
          calls++;
          return calls < 3
              ? http.Response('', 429, headers: {'retry-after': '0'})
              : hits('words');
        }),
      );

      final lyrics = await source.find(song);

      expect(lyrics!.lines.single.text, 'words');
      expect(calls, 3);
    });

    test('a sheet opened again joins the request that is still out', () async {
      var calls = 0;
      final source = LrclibLyrics(
        client: MockClient((_) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return hits('words');
        }),
      );

      final first = source.find(song);
      final second = source.find(song);

      expect((await first)!.lines.single.text, 'words');
      expect((await second)!.lines.single.text, 'words');
      expect(calls, 1);
    });

    test('a failure is said, and the next open asks again', () async {
      var down = true;
      var calls = 0;
      final source = LrclibLyrics(
        retryDelay: Duration.zero,
        client: MockClient((_) async {
          calls++;
          return down ? http.Response('', 502) : hits('words');
        }),
      );

      await expectLater(source.find(song), throwsA(isA<LyricsUnavailable>()));
      expect(calls, 3);

      down = false;
      expect((await source.find(song))!.lines.single.text, 'words');
    });

    test('a song LRCLIB does not have is not asked for twice', () async {
      var calls = 0;
      final source = LrclibLyrics(
        client: MockClient((_) async {
          calls++;
          return http.Response('[]', 200);
        }),
      );

      expect(await source.find(song), isNull);
      expect(await source.find(song), isNull);
      expect(calls, 1);
    });
  });
}
