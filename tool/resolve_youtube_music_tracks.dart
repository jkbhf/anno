// Fills in missing YouTube Music video ids in the song catalogs under
// assets/songs/.
//
//   dart run tool/resolve_youtube_music_tracks.dart [assets/songs/esc.json ...]
//   dart run tool/resolve_youtube_music_tracks.dart --only=1971,Chai
//
// Goes through the search of music.youtube.com itself - the endpoint its web
// player calls, which needs no key and has no daily quota. The official Data
// API would do the same at 100 searches a day, which is two weeks for the
// catalogs. The price is that the endpoint is not documented and can change;
// that only ever breaks this tool, never the game, which opens plain links.
//
// The search is asked for songs only, not videos: that answers with the album
// recording rather than a music video with a spoken intro, a live cut or a fan
// upload. A hit is taken on the same test as for Spotify - artist and title
// both match, and neither title nor album says karaoke, remix or live.
//
// Unlike Spotify, a miss here is not a swap. The catalogs are curated against
// Spotify (CLAUDE.md, "What Spotify does not carry is not a card"); an entry
// YouTube Music does not have still plays there by search, and a song does not
// leave the deck over it.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'resolve_spotify_tracks.dart'
    show
        artistMatches,
        artistParts,
        flatten,
        notTheSong,
        titleMatches,
        titleUnreadable;

/// There is no documented limit, so the pace is the one that kept Spotify
/// friendly. A pass over every catalog is a quarter of an hour.
const requestGap = Duration(milliseconds: 350);

/// The `params` the web player sends for the "Songs" filter.
const songsOnly = 'EgWKAQIIAWoKEAMQBBAJEAoQBQ==';

/// Failures in a row after which the run stops: that is a block or a changed
/// endpoint, not a string of unlucky songs.
const failuresInARow = 5;

/// One song row of a search result.
class YouTubeSong {
  const YouTubeSong({
    required this.videoId,
    required this.title,
    required this.artists,
    this.album,
  });

  final String videoId;
  final String title;
  final List<String> artists;
  final String? album;

  @override
  String toString() => '$title - ${artists.join(', ')} / $album [$videoId]';
}

class RequestFailed implements Exception {
  const RequestFailed(this.status);

  final int status;

  @override
  String toString() => 'YouTube Music answered $status';
}

/// The song rows out of a search response, in the order they came.
///
/// Rows without a video id or greyed out - not playable in the country the
/// search was made for - are left out, they would be a round without a song.
List<YouTubeSong> parseSearch(Map<String, dynamic> body) {
  final rows = <Map<String, dynamic>>[];
  void collect(Object? node) {
    if (node is Map<String, dynamic>) {
      final row = node['musicResponsiveListItemRenderer'];
      if (row is Map<String, dynamic>) rows.add(row);
      node.values.forEach(collect);
    } else if (node is List) {
      node.forEach(collect);
    }
  }

  collect(body);

  return [for (final row in rows) ?_parseRow(row)];
}

YouTubeSong? _parseRow(Map<String, dynamic> row) {
  final videoId = row['playlistItemData']?['videoId'];
  if (videoId is! String) return null;
  final policy = row['musicItemRendererDisplayPolicy'];
  if (policy is String && policy.contains('GREY_OUT')) return null;

  final columns = (row['flexColumns'] as List?) ?? const [];
  List<Map<String, dynamic>> runs(int index) => index < columns.length
      ? ((columns[index]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                    as List?) ??
                const [])
            .cast<Map<String, dynamic>>()
      : const [];

  final title = runs(0).map((run) => run['text']).join();
  if (title.isEmpty) return null;

  // "Lena", " • ", "My Cassette Player", " • ", "2:56" - the artists are
  // everything before the first dot, joined by ", " and " & " runs.
  final artists = <String>[];
  String? album;
  var group = 0;
  for (final run in runs(1)) {
    final text = run['text'] as String;
    if (text.trim() == '•') {
      group++;
      continue;
    }
    final page =
        run['navigationEndpoint']?['browseEndpoint']?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType'];
    if (page == 'MUSIC_PAGE_TYPE_ALBUM') {
      album = text;
    } else if (group == 0 && !const [', ', ' & ', ' and '].contains(text)) {
      artists.add(text);
    }
  }

  return YouTubeSong(
    videoId: videoId,
    title: title,
    artists: artists,
    album: album,
  );
}

/// A live cut says so in a bracket or after a dash, never in the words the
/// title is compared on - `normalize` throws both away, so "Satellite (Live)"
/// would pass for "Satellite". "Live Is Life" still does.
final _live = RegExp(r'[(\[][^)\]]*\blive\b|\s-\s.*\blive\b');

/// What YouTube Music carries far more of than Spotify: the artist's own
/// second take of the song, uploaded next to the original and ranked above it
/// often enough - "Tattoo (Acoustic)" came back for Jordin Sparks.
const notTheSongHere = [
  'acoustic',
  'unplugged',
  'sped up',
  'slowed',
  're-recorded',
  'rerecorded',
  'piano version',
  'orchestral',
  'lullaby',
];

bool isTheRecording(YouTubeSong song) {
  final title = flatten(song.title);
  final album = flatten(song.album ?? '');
  final haystack = '$title $album';
  if (notTheSong.any(haystack.contains)) return false;
  if (notTheSongHere.any(haystack.contains)) return false;
  return !_live.hasMatch(title) && !_live.hasMatch(album);
}

var requestCount = 0;

Future<List<YouTubeSong>> search(String query) async {
  await Future<void>.delayed(requestGap);
  requestCount++;
  final response = await http.post(
    Uri.parse('https://music.youtube.com/youtubei/v1/search?prettyPrint=false'),
    headers: {
      'Content-Type': 'application/json',
      'Origin': 'https://music.youtube.com',
    },
    body: jsonEncode({
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20260901.01.00',
          'hl': 'en',
          // Where the room is: a song greyed out in Germany is no card.
          'gl': 'DE',
        },
      },
      'query': query,
      'params': songsOnly,
    }),
  );
  if (response.statusCode != 200) throw RequestFailed(response.statusCode);
  return parseSearch(
    jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
  );
}

/// The entry's own recording, or null when YouTube Music has none.
///
/// The first row is not trusted any more than Spotify's first hit is: every
/// candidate is checked against artist, title and pressing.
Future<YouTubeSong?> findSong(String title, String artist) async {
  final parts = artistParts(artist);
  final seen = <String>{};
  final queries = [
    '$title $artist',
    if (parts.isNotEmpty) '$title ${parts.first}',
  ].where((query) => seen.add(query.toLowerCase()));

  for (final query in queries) {
    for (final song in await search(query)) {
      if (!isTheRecording(song)) continue;
      if (!artistMatches(artist, song.artists)) continue;
      if (!titleMatches(title, song.title) && !titleUnreadable(song.title)) {
        continue;
      }
      return song;
    }
  }
  return null;
}

/// The entry with the id put in right after the Spotify one, so the two ids of
/// an entry stay next to each other in the file.
Map<String, dynamic> withVideoId(Map<String, dynamic> song, String id) {
  final out = <String, dynamic>{};
  for (final MapEntry(:key, :value) in song.entries) {
    if (key == 'youtubeVideoId') continue;
    out[key] = value;
    if (key == 'spotifyTrackId') out['youtubeVideoId'] = id;
  }
  out.putIfAbsent('youtubeVideoId', () => id);
  return out;
}

Future<void> _write(File file, Map<String, dynamic> catalog) async {
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(catalog)}\n',
  );
  stdout.writeln('${file.path} updated.');
}

Future<void> main(List<String> args) async {
  final only = args
      .firstWhere((arg) => arg.startsWith('--only='), orElse: () => '')
      .replaceFirst('--only=', '')
      .split(',')
      .map((term) => term.trim().toLowerCase())
      .where((term) => term.isNotEmpty)
      .toList();

  bool wanted(Map<String, dynamic> song) {
    if (only.isEmpty) return true;
    final haystack = '${song['year']} ${song['title']} ${song['artist']}'
        .toLowerCase();
    return only.any(haystack.contains);
  }

  final paths = args.where((arg) => !arg.startsWith('--')).toList();
  final files = paths.isNotEmpty
      ? paths.map(File.new).toList()
      : Directory('assets/songs')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList();

  final missing = <String>[];
  final unchecked = <String>[];
  var resolved = 0;
  var failures = 0;

  for (final file in files) {
    final catalog =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final songs = (catalog['songs'] as List).cast<Map<String, dynamic>>();
    var changed = false;

    for (final (index, song) in songs.indexed) {
      final existing = song['youtubeVideoId'];
      if (existing is String && existing.isNotEmpty) continue;
      if (!wanted(song)) continue;

      final title = song['title'] as String;
      final artist = song['artist'] as String;
      final label = '${catalog['id']} · ${song['year']} · $title - $artist';
      final YouTubeSong? hit;
      try {
        hit = await findSong(title, artist);
        failures = 0;
      } on Exception catch (error) {
        unchecked.add('$label: $error');
        if (++failures >= failuresInARow) {
          if (changed) await _write(file, catalog);
          stderr.writeln(
            '\n$failuresInARow requests in a row failed ($error). '
            'Everything found up to here has been written.',
          );
          exit(2);
        }
        continue;
      }
      if (hit == null) {
        missing.add(label);
        continue;
      }

      songs[index] = withVideoId(song, hit.videoId);
      changed = true;
      resolved++;
      // Every hit on one line, so a wrong one can be caught reading down the
      // run rather than by opening a hundred links.
      stdout.writeln('  $label -> ${hit.title} / ${hit.artists.join(', ')}');
    }

    if (changed) await _write(file, catalog);
  }

  stdout.writeln(
    '\n$resolved video ids added, ${missing.length} without a song, '
    '$requestCount requests spent.',
  );
  if (missing.isNotEmpty) {
    stdout.writeln(
      '\nNot on YouTube Music - leave them, the round falls back to the '
      'search:',
    );
    for (final line in missing) {
      stdout.writeln('  $line');
    }
  }
  if (unchecked.isNotEmpty) {
    stdout.writeln('\nCould not be looked up - run again:');
    for (final line in unchecked) {
      stdout.writeln('  $line');
    }
  }
}
