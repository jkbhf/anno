import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/song.dart';

/// One line of a song's text. [time] is where it starts in the recording, or
/// null when the source only has the words.
@immutable
class LyricsLine {
  const LyricsLine(this.text, {this.time});

  final String text;
  final Duration? time;
}

/// The text of a song, line by line.
@immutable
class Lyrics {
  const Lyrics(this.lines, {this.instrumental = false});

  /// Reads an LRC text: `[mm:ss.xx] words`, one timestamp or several per line.
  /// Tags without a time (`[ar:...]`) and empty lines are dropped.
  factory Lyrics.fromLrc(String lrc) {
    final stamp = RegExp(r'\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\]');
    final lines = <LyricsLine>[];
    for (final raw in const LineSplitter().convert(lrc)) {
      final stamps = stamp.allMatches(raw).toList();
      if (stamps.isEmpty) continue;
      final text = raw.substring(stamps.last.end).trim();
      for (final match in stamps) {
        final fraction = match.group(3) ?? '0';
        lines.add(
          LyricsLine(
            text,
            time: Duration(
              minutes: int.parse(match.group(1)!),
              seconds: int.parse(match.group(2)!),
              // `.5`, `.50` and `.500` are all half a second.
              milliseconds: int.parse(fraction.padRight(3, '0')),
            ),
          ),
        );
      }
    }
    lines.sort((a, b) => a.time!.compareTo(b.time!));
    return Lyrics(lines);
  }

  factory Lyrics.plain(String text) => Lyrics([
    for (final line in const LineSplitter().convert(text.trim()))
      LyricsLine(line.trim()),
  ]);

  final List<LyricsLine> lines;

  /// The song has no words. Said rather than shown as an empty sheet.
  final bool instrumental;

  /// True when every line knows where it starts, so the sheet can follow the
  /// player.
  bool get isSynced =>
      lines.isNotEmpty && lines.every((line) => line.time != null);

  /// The line being sung at [position], or -1 before the first one.
  int lineAt(Duration position) {
    var current = -1;
    for (var i = 0; i < lines.length; i++) {
      final time = lines[i].time;
      if (time == null || time > position) break;
      current = i;
    }
    return current;
  }
}

/// Where the text of a song comes from.
///
/// Spotify shows lyrics in its own apps, but its Web API has no endpoint for
/// them - what the client uses is private and tied to its own token. So the
/// words come from elsewhere, and the Spotify part is the timing: a synced text
/// follows the player in this tab.
abstract class LyricsSource {
  /// The text of [song], or null when the source has none. [duration] is the
  /// length of the recording that plays, when it is known, so a synced text
  /// for a different cut is not laid over it.
  Future<Lyrics?> find(Song song, {Duration? duration});
}

/// The one source the game uses, kept for the whole visit so its cache is.
final LyricsSource sharedLyrics = LrclibLyrics();

/// [LRCLIB](https://lrclib.net): open, no key, CORS allowed, and synced texts
/// for most of what the decks hold.
class LrclibLyrics implements LyricsSource {
  LrclibLyrics({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// One evening asks for the same song twice at most - but the sheet is opened
  /// and closed again, and that should not go out again each time.
  final Map<String, Lyrics?> _cache = {};

  static const String _host = 'lrclib.net';

  /// How far a synced text's length may be off the recording before it is not
  /// trusted to follow it. Radio edit against album version is more than that.
  static const Duration _durationSlack = Duration(seconds: 5);

  @override
  Future<Lyrics?> find(Song song, {Duration? duration}) async {
    final key = song.key;
    if (_cache.containsKey(key)) return _cache[key];
    final found = await _lookUp(song, duration);
    // A failed request is not cached: the next open asks again.
    if (found != _failed) _cache[key] = found;
    return found == _failed ? null : found;
  }

  static const Lyrics _failed = Lyrics([]);

  Future<Lyrics?> _lookUp(Song song, Duration? duration) async {
    try {
      final response = await _client.get(
        Uri.https(_host, '/api/search', {
          'track_name': song.title,
          'artist_name': song.artist,
        }),
      );
      if (response.statusCode != 200) return _failed;
      final results = (jsonDecode(response.body) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      return pick(results, duration);
    } on Object catch (error) {
      debugPrint('Lyrics for $song not readable: $error');
      return _failed;
    }
  }

  /// The best of LRCLIB's search hits: a synced text that fits the length of
  /// the recording, else any text at all.
  @visibleForTesting
  static Lyrics? pick(List<Map<String, dynamic>> results, Duration? duration) {
    bool fits(Map<String, dynamic> hit) {
      final seconds = hit['duration'];
      if (duration == null || duration == Duration.zero || seconds is! num) {
        return true;
      }
      final length = Duration(milliseconds: (seconds * 1000).round());
      return (length - duration).abs() <= _durationSlack;
    }

    String? text(Map<String, dynamic> hit, String field) {
      final value = hit[field];
      return value is String && value.trim().isNotEmpty ? value : null;
    }

    for (final hit in results) {
      final synced = text(hit, 'syncedLyrics');
      if (synced != null && fits(hit)) {
        final lyrics = Lyrics.fromLrc(synced);
        if (lyrics.isSynced) return lyrics;
      }
    }
    for (final hit in results) {
      final plain = text(hit, 'plainLyrics');
      if (plain != null) return Lyrics.plain(plain);
    }
    // A synced text for another cut is still the right words.
    for (final hit in results) {
      final synced = text(hit, 'syncedLyrics');
      if (synced != null) {
        return Lyrics.plain(
          Lyrics.fromLrc(synced).lines.map((line) => line.text).join('\n'),
        );
      }
    }
    if (results.any((hit) => hit['instrumental'] == true)) {
      return const Lyrics([], instrumental: true);
    }
    return null;
  }
}
