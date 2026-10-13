import 'package:flutter_test/flutter_test.dart';
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
}
