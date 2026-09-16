// Fills in missing YouTube Music video ids in the song catalogs under
// assets/songs/.
//
//   dart run tool/resolve_youtube_music_tracks.dart [assets/songs/esc.json ...]
//   dart run tool/resolve_youtube_music_tracks.dart --only=1971,Chai
//   dart run tool/resolve_youtube_music_tracks.dart --curl   # see [useCurl]
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
        normalize,
        notTheSong,
        titleMatches;

/// There is no documented limit, so the pace is the one that kept Spotify
/// friendly. A pass over every catalog is a quarter of an hour.
const requestGap = Duration(milliseconds: 350);

/// The `params` the web player sends for the "Songs" filter.
const songsOnly = 'EgWKAQIIAWoKEAMQBBAJEAoQBQ==';

/// The same for "Videos" - the second try, see [findSong].
const videosOnly = 'EgWKAQIQAWoKEAMQBBAJEAoQBQ==';

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
  'acappella',
  'a cappella',
  'unplugged',
  'sped up',
  'slowed',
  're-recorded',
  'rerecorded',
  'piano version',
  'orchestral',
  'lullaby',
  'maxi',
  'long version',
  'neue version',
  "taylor's version",
  'zeitlos version',
  'raw sessions',
  'studio recording',
  'version mto',
  'kinderversion',
  'kinder version',
  'nl version',
  'japanese ver',
  'chinese ver',
  'english ver',
  'spanish ver',
  'french ver',
];

/// A take in another language is another song to the room - Lulu's "Boom Bang
/// a Bang (Deutsch Version)" is not what Madrid heard in 1969. Except in the
/// German deck, where the German version is the one the card is about.
const germanVersion = ['deutsche version', 'deutsch version', 'german version'];

/// What a bracket or a dash suffix of the title says about the pressing.
final _suffix = RegExp(r'[(\[]([^)\]]*)[)\]]|\s-\s(.*)$');

/// A mix is the song when it is the one that was on the radio - "Radio Mix",
/// "7\" Mix", "Single Mix" - and a remix under another name otherwise: "Motiv8
/// Extended Vocal Mix", "Nite Mix", "Special 12\" Dance Mix" all came back
/// as the entry before this check.
const _mixThatIsTheSong = [
  'radio',
  'single',
  '7"',
  'video',
  'album',
  'original',
  'edit',
  'lp',
  'eurovision',
  'stereo',
  'mono',
];

/// A suffix that only credits somebody.
final _guest = RegExp(r'^\s*(feat\.?|featuring|with)\s');

/// Suffixes that are a remix whatever else they say.
final _remix = RegExp(r'\brmx\b|\bextended\b|\bdj\s');

/// A four digit year in a suffix.
final _year = RegExp(r'\b(19[5-9]\d|20\d\d)\b');

/// True when the row is the recording and not another take of it.
///
/// [year] is the catalog year. A suffix naming a later one is a re-recording -
/// "MfG (2022)", "O mein Papa (Version 2008)" - while one naming the year
/// itself, "Looking High, High, High (1960)", only dates the original.
///
/// Whatever the catalog [title] says itself is no objection: "All Too Well
/// (Taylor's Version)" is the entry, "Mine (Taylor's Version)" is not. [deck]
/// is the catalog id, for [germanVersion].
bool isTheRecording(
  YouTubeSong song, {
  int? year,
  String title = '',
  String deck = '',
}) {
  final name = flatten(song.title);
  final album = flatten(song.album ?? '');
  final wanted = flatten(title);
  final haystack = '$name $album';
  bool refuses(String word) =>
      haystack.contains(word) && !wanted.contains(word);

  if (notTheSong.any(refuses)) return false;
  if (notTheSongHere.any(refuses)) return false;
  if (deck != 'german_songs' && germanVersion.any(refuses)) return false;
  if (_live.hasMatch(name) || _live.hasMatch(album)) return false;

  for (final match in _suffix.allMatches(name)) {
    final suffix = match.group(1) ?? match.group(2) ?? '';
    if (wanted.contains(suffix)) continue;
    // A guest is not a pressing: "Lean On (feat. DJ Snake)".
    if (_guest.hasMatch(suffix)) continue;
    if (_remix.hasMatch(suffix)) return false;
    if (suffix.contains('mix') && !_mixThatIsTheSong.any(suffix.contains)) {
      return false;
    }
    // A remaster is the old recording with a new date on it, "Love Me Do
    // (Remastered 2009)" - the year there says nothing about the song.
    if (year != null && !suffix.contains('remaster')) {
      for (final found in _year.allMatches(suffix)) {
        if (int.parse(found.group(1)!) > year + 1) return false;
      }
    }
  }
  return true;
}

var requestCount = 0;

const browserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/140.0 Safari/537.36';

/// Send the searches through curl instead of `package:http` - `--curl`.
///
/// After a couple of thousand searches Google started answering the Dart
/// client with its "Sorry..." bot page, a browser user agent did not help, and
/// the very same request from curl went through. The block wears off on its
/// own after a while; this is the way to carry on without waiting for it.
var useCurl = false;

const _searchUrl =
    'https://music.youtube.com/youtubei/v1/search?prettyPrint=false';

Future<List<YouTubeSong>> search(
  String query, {
  String filter = songsOnly,
}) async {
  await Future<void>.delayed(requestGap);
  requestCount++;
  final body = jsonEncode({
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
    'params': filter,
  });
  const headers = {
    'Content-Type': 'application/json',
    'Origin': 'https://music.youtube.com',
    'User-Agent': browserAgent,
  };

  final String text;
  if (useCurl) {
    final process = await Process.start('curl', [
      '-s',
      '-X',
      'POST',
      _searchUrl,
      for (final MapEntry(:key, :value) in headers.entries) ...[
        '-H',
        '$key: $value',
      ],
      '--data-binary',
      '@-',
      '-w',
      '\n%{http_code}',
    ]);
    process.stdin.add(utf8.encode(body));
    await process.stdin.close();
    final out = await process.stdout.transform(utf8.decoder).join();
    await process.exitCode;
    final split = out.lastIndexOf('\n');
    final status = int.tryParse(out.substring(split + 1).trim()) ?? 0;
    if (status != 200) throw RequestFailed(status);
    text = out.substring(0, split);
  } else {
    final response = await http.post(
      Uri.parse(_searchUrl),
      headers: headers,
      body: body,
    );
    if (response.statusCode != 200) throw RequestFailed(response.statusCode);
    text = utf8.decode(response.bodyBytes);
  }
  return parseSearch(jsonDecode(text) as Map<String, dynamic>);
}

/// True when the two name the same song - [titleMatches], or the same letters
/// with the spaces and dashes in other places: the catalog has
/// "Maschendrahtzaun", YouTube Music "Maschen-Draht-Zaun".
///
/// A title in Hangul carries its English name in the bracket - "불장난(Playing
/// With Fire)" - and [normalize] throws the bracket away with nothing left
/// outside it. Then the bracket is the title.
bool sameTitle(String catalog, String found) {
  if (titleMatches(catalog, found) ||
      normalize(catalog).replaceAll(' ', '') ==
          normalize(found).replaceAll(' ', '')) {
    return true;
  }
  if (normalize(found).isNotEmpty) return false;
  final bracket = RegExp(r'[(\[]([^)\]]+)[)\]]').firstMatch(found);
  return bracket != null && titleMatches(catalog, bracket.group(1)!);
}

/// True when a row is the entry: the recording, the title and the artist.
///
/// Both ways out of a name that cannot be compared are closed, unlike in the
/// Spotify resolver. A title nothing is left of - "Water" came back as "Само
/// Шампиони" - because a search here answers with the artist's whole catalog.
/// An artist nothing is left of - "A-Ba-Ni-Bi" came back from a Thai artist -
/// because a cover carries the same title. Those entries go to the search in
/// the game instead.
bool isTheEntry(
  YouTubeSong song,
  String title,
  String artist, {
  int? year,
  String deck = '',
}) =>
    isTheRecording(song, year: year, title: title, deck: deck) &&
    sameTitle(title, song.title) &&
    artistMatches(artist, song.artists);

/// A music video is titled for the channel page, "Dua Lipa - New Rules
/// (Official Music Video)". The brackets go in [normalize]; the artist in
/// front has to go here, or the title left over is "Dua Lipa".
YouTubeSong asVideo(YouTubeSong video, String artist) {
  final dash = video.title.indexOf(' - ');
  if (dash == -1) return video;
  final front = video.title.substring(0, dash);
  if (!artistMatches(artist, [front])) return video;
  return YouTubeSong(
    videoId: video.videoId,
    title: video.title.substring(dash + 3),
    artists: video.artists,
    album: video.album,
  );
}

/// The entry's own recording, or null when YouTube Music has none.
///
/// The first row is not trusted any more than Spotify's first hit is: every
/// candidate is checked against artist, title and pressing.
///
/// Songs first, the music video second. The album recording is the better
/// card, but some labels do not let it into the German catalog at all while
/// the video stands right next to it - "New Rules" answers with covers and a
/// remix from Germany and with the song from the US. A video on the artist's
/// own channel is the same song with a longer intro, and far better than the
/// search page the round would land on otherwise.
Future<YouTubeSong?> findSong(
  String title,
  String artist, {
  required int year,
  required String deck,
}) async {
  final parts = artistParts(artist);
  final seen = <String>{};
  final queries = [
    '$title $artist',
    if (parts.isNotEmpty) '$title ${parts.first}',
  ].where((query) => seen.add(query.toLowerCase()));

  for (final query in queries) {
    for (final song in await search(query)) {
      if (isTheEntry(song, title, artist, year: year, deck: deck)) {
        return song;
      }
    }
  }
  for (final row in await search('$title $artist', filter: videosOnly)) {
    final video = asVideo(row, artist);
    if (isTheEntry(video, title, artist, year: year, deck: deck)) {
      return video;
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
  useCurl = args.contains('--curl');
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
        hit = await findSong(
          title,
          artist,
          year: song['year'] as int,
          deck: catalog['id'] as String,
        );
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
