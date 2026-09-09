// Fills in missing Spotify track ids in the song catalogs under assets/songs/.
//
//   export SPOTIFY_CLIENT_ID=...
//   export SPOTIFY_CLIENT_SECRET=...
//   dart run tool/resolve_spotify_tracks.dart [assets/songs/esc.json ...]
//   dart run tool/resolve_spotify_tracks.dart --recheck [files...]
//
// Uses the client credentials flow: that is enough for the search and needs no
// logged in user. Songs that already carry an id are left alone, unless
// --recheck is given - that one reads every id back and drops the ones that
// point at the wrong song.
//
// A hit is only taken when artist and title both match and the pressing is the
// song itself rather than a karaoke, tribute, medley or remix version. What is
// left over is listed at the end: those entries have no song to play, and the
// catalog rule for them is a swap, not a search by hand - see CLAUDE.md,
// "What Spotify does not carry is not a card".

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Spotify answers a burst with a lockout of a day, so the requests are spaced
/// out and a 429 ends the run instead of waiting it out.
///
/// 120ms was still too fast: a fill and a recheck back to back bought a lockout
/// of 24 hours. A full pass over a catalog is a couple of minutes at this pace,
/// which is nothing next to waiting a day for the next attempt.
const requestGap = Duration(milliseconds: 350);

/// How many hits a search may ask for. Anything above this is answered with
/// `400 Invalid limit` - the documented maximum of 50 is not what an app in
/// development mode gets, and asking for it fails every single search.
const searchLimit = 10;

/// Album or track names that mean this is not the recording of the entry.
const notTheSong = [
  'karaoke',
  'in the style of',
  'originally performed',
  'made famous by',
  'as made famous',
  'tribute',
  'instrumental',
  'playback',
  'medley',
  'remix',
  'nightcore',
  'cover version',
];

/// A request that came back with neither a result nor a rate limit.
///
/// It has to be told apart from an empty result: a song whose search failed is
/// unknown, and calling it "not on Spotify" would swap out a good entry over a
/// bad request.
class RequestFailed implements Exception {
  const RequestFailed(this.status, this.path);

  final int status;
  final String path;

  @override
  String toString() => 'Spotify answered $status for $path';
}

class RateLimited implements Exception {
  const RateLimited(this.retryAfter);

  final Duration retryAfter;

  @override
  String toString() =>
      'Spotify is rate limiting this app for another '
      '${retryAfter.inMinutes} minutes. Try again later.';
}

Future<String> fetchToken(String id, String secret) async {
  final response = await http.post(
    Uri.parse('https://accounts.spotify.com/api/token'),
    headers: {
      'Authorization': 'Basic ${base64Encode(utf8.encode('$id:$secret'))}',
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: {'grant_type': 'client_credentials'},
  );
  if (response.statusCode != 200) {
    throw Exception(
      'Token request failed (${response.statusCode}): ${response.body}',
    );
  }
  return jsonDecode(response.body)['access_token'] as String;
}

Future<Map<String, dynamic>> _api(String token, String path) async {
  await Future<void>.delayed(requestGap);
  final response = await http.get(
    Uri.parse('https://api.spotify.com/v1$path'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (response.statusCode == 429) {
    final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 0;
    throw RateLimited(Duration(seconds: seconds));
  }
  if (response.statusCode != 200) {
    throw RequestFailed(response.statusCode, path);
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

/// Lowercase, without accents and without anything that only tells two
/// spellings of the same title apart. Keeps brackets and suffixes.
String flatten(String value) {
  const accents = 'àáâãäåçèéêëìíîïñòóôõöøùúûüýÿšžğışłđčćř';
  const plain = 'aaaaaaceeeeiiiinoooooouuuuyyszgisldccr';
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().replaceAll('ß', 'ss').runes) {
    final char = String.fromCharCode(rune);
    final index = accents.indexOf(char);
    buffer.write(index == -1 ? char : plain[index]);
  }
  return buffer.toString();
}

/// [flatten], and additionally without brackets and without a trailing
/// " - Remastered 2016" - what is left is the title itself.
String normalize(String value) {
  var out = flatten(value);
  out = out.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ');
  out = out.replaceAll(RegExp(r' - .*$'), ' ');
  out = out.replaceAll(RegExp('[^a-z0-9]+'), ' ');
  return out.trim();
}

/// The single names a catalog artist string can match, so "Ell & Nikki" also
/// matches a track credited to "Ell" alone.
List<String> artistParts(String artist) => artist
    .split(
      RegExp(r'\s*(?:&|,|/|\bfeat\.?\b|\bfeaturing\b|\band\b|\bwith\b)\s*'),
    )
    .map(normalize)
    .where((part) => part.isNotEmpty)
    .toList();

/// True when one name is the other, or contains it as whole words: "Max" is
/// "Max Mutzke", but "Blue" is not "Adele" and "Vikki" is not "Vicky Leandros".
bool _looseMatch(String a, String b) =>
    a == b || _containsWords(a, b) || _containsWords(b, a);

bool _containsWords(String haystack, String needle) =>
    needle.isNotEmpty &&
    (haystack.startsWith('$needle ') ||
        haystack.endsWith(' $needle') ||
        haystack.contains(' $needle '));

bool artistMatches(String catalog, List<String> credited) {
  final wanted = artistParts(catalog);
  for (final part in wanted) {
    for (final name in credited.map(normalize)) {
      if (_looseMatch(part, name)) return true;
    }
  }
  return false;
}

/// True when the two name the same song.
///
/// Word for word, give or take one: catalogs and Spotify disagree by a single
/// word all the time - "Si la vie est cadeau" against "Si la vie est un
/// cadeau", "Serving" against "SERVING KANT", a "geh'n" that Spotify cut to
/// "Geh". Two words apart is another song, which is what keeps "I Can" away
/// from "I Can't Wait" and "Chai" away from "Ayelet Chen".
///
/// One word of slack does let "Love Is..." through to "Love Is Blue" - the
/// artist is what separates those two, and every caller checks it.
bool titleMatches(String catalog, String spotify) {
  final a = _words(catalog);
  final b = _words(spotify);
  if (a.isEmpty || b.isEmpty) return false;
  final (short, long) = a.length <= b.length ? (a, b) : (b, a);
  if (long.length - short.length > 1) return false;
  return _isSubsequence(short, long);
}

List<String> _words(String value) {
  final normalized = normalize(value);
  return normalized.isEmpty ? const [] : normalized.split(' ');
}

/// True when every word of [short] turns up in [long], in that order.
bool _isSubsequence(List<String> short, List<String> long) {
  var index = 0;
  for (final word in long) {
    if (index < short.length && short[index] == word) index++;
  }
  return index == short.length;
}

/// True when a Spotify title says nothing either way, because it is written in
/// a script that [normalize] leaves nothing of - Hebrew, Cyrillic, Greek.
///
/// The entries are in transcription ("Milim", "Hora"), Spotify carries them as
/// מילים and הורה, and the two can never be compared. The artist has to carry
/// the match there, and an id like that is kept rather than thrown away.
bool titleUnreadable(String spotify) => normalize(spotify).isEmpty;

/// A karaoke or nightcore version says so in a bracket, and [normalize] throws
/// brackets away - so this one reads the name as it stands.
bool isTheRecording(Map<String, dynamic> track) {
  final haystack =
      '${flatten(track['name'] as String)} '
      '${flatten((track['album']?['name'] as String?) ?? '')}';
  return !notTheSong.any(haystack.contains);
}

List<String> creditsOf(Map<String, dynamic> track) => [
  for (final artist in (track['artists'] as List).cast<Map<String, dynamic>>())
    artist['name'] as String,
];

Future<List<Map<String, dynamic>>> _search(String token, String query) async {
  final encoded = Uri.encodeQueryComponent(query);
  final body = await _api(
    token,
    '/search?q=$encoded&type=track&limit=$searchLimit',
  );
  return (body['tracks']['items'] as List).cast<Map<String, dynamic>>();
}

/// The entry's own recording, or null when Spotify does not carry it.
///
/// The field values have to be quoted: `track:Diese Welt` searches for "Diese"
/// and drops the rest into a free text match, which is how a search for Katja
/// Ebstein used to come back with Fettes Brot. And the first hit is never good
/// enough on its own - an unquoted search for Blue's "I Can" answers with
/// Adele - so every candidate is checked against artist, title and pressing.
Future<Map<String, dynamic>?> searchTrack(
  String token,
  String title,
  String artist,
) async {
  final first = artistParts(artist).isEmpty
      ? artist
      : artistParts(artist).first;
  final queries = [
    'track:"$title" artist:"$artist"',
    'track:"$title" artist:"$first"',
    'artist:"$artist" $title',
    'track:"$title"',
  ];

  for (final query in queries) {
    for (final track in await _search(token, query)) {
      final name = track['name'] as String;
      if (!isTheRecording(track)) continue;
      if (!artistMatches(artist, creditsOf(track))) continue;
      if (!titleMatches(title, name) && !titleUnreadable(name)) continue;
      return track;
    }
  }
  return null;
}

/// The track behind an id, or null when Spotify does not know it any more.
Future<Map<String, dynamic>?> fetchTrack(String token, String id) async {
  try {
    return await _api(token, '/tracks/$id');
  } on RequestFailed catch (error) {
    if (error.status == 404) return null;
    rethrow;
  }
}

Future<void> _write(File file, Map<String, dynamic> catalog) async {
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(catalog)}\n',
  );
  stdout.writeln('${file.path} updated.');
}

/// Why an id that is already in the catalog cannot stay, or null when it can.
///
/// A wrong title or a karaoke pressing is decided here; a name that does not
/// line up is not. Artists get renamed (Charlotte Nilsson became Charlotte
/// Perrelli), transliterated and credited in Hebrew, and throwing those ids
/// away would cost the game more songs than the odd wrong hit does.
String? cannotStay(Map<String, dynamic> song, Map<String, dynamic>? track) {
  if (track == null) return 'id points at nothing';
  final title = song['title'] as String;
  final name = track['name'] as String;
  if (!titleMatches(title, name) && !titleUnreadable(name)) {
    return 'is "$name"';
  }
  if (!isTheRecording(track)) {
    return 'is "${track['name']}" / ${track['album']?['name']}';
  }
  return null;
}

/// Reads every id in the catalogs back, clears the ones that point at another
/// song and reports the ones that only look odd. The next plain run fills the
/// cleared entries in again - or, where Spotify has nothing, they get swapped.
Future<int> recheck(String token, List<File> files) async {
  var cleared = 0;
  final review = <String>[];

  for (final file in files) {
    final catalog =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final songs = (catalog['songs'] as List).cast<Map<String, dynamic>>();
    var changed = false;

    for (final song in songs) {
      final id = song['spotifyTrackId'];
      if (id is! String || id.isEmpty) continue;

      final Map<String, dynamic>? track;
      try {
        track = await fetchTrack(token, id);
      } on RateLimited {
        if (changed) await _write(file, catalog);
        rethrow;
      } on RequestFailed catch (error) {
        // Unknown, not wrong: leave the id where it is and say so.
        review.add('${catalog['id']} · ${song['title']}: $error');
        continue;
      }

      final title = song['title'] as String;
      final artist = song['artist'] as String;
      final reason = cannotStay(song, track);
      if (reason != null) {
        stdout.writeln('  cleared $title - $artist: $reason');
        song.remove('spotifyTrackId');
        changed = true;
        cleared++;
        continue;
      }
      if (!artistMatches(artist, creditsOf(track!))) {
        review.add(
          '${catalog['id']} · $title - $artist: credited to '
          '${creditsOf(track).join(', ')} [$id]',
        );
      }
    }

    if (changed) await _write(file, catalog);
  }

  if (review.isNotEmpty) {
    stdout.writeln('\nSame title, another name - check by hand:');
    for (final line in review) {
      stdout.writeln('  $line');
    }
  }

  return cleared;
}

Future<void> main(List<String> args) async {
  final id = Platform.environment['SPOTIFY_CLIENT_ID'];
  final secret = Platform.environment['SPOTIFY_CLIENT_SECRET'];
  if (id == null || secret == null) {
    stderr.writeln('Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET.');
    exit(1);
  }

  final paths = args.where((arg) => !arg.startsWith('--')).toList();
  final files = paths.isNotEmpty
      ? paths.map(File.new).toList()
      : Directory('assets/songs')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList();

  final token = await fetchToken(id, secret);

  try {
    if (args.contains('--recheck')) {
      final cleared = await recheck(token, files);
      stdout.writeln('$cleared ids cleared.');
      return;
    }

    final review = <String>[];
    final swap = <String>[];
    final unchecked = <String>[];
    var resolved = 0;

    for (final file in files) {
      final catalog =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final songs = (catalog['songs'] as List).cast<Map<String, dynamic>>();
      var changed = false;

      for (final song in songs) {
        final existing = song['spotifyTrackId'];
        if (existing is String && existing.isNotEmpty) continue;

        final title = song['title'] as String;
        final artist = song['artist'] as String;
        final Map<String, dynamic>? track;
        try {
          track = await searchTrack(token, title, artist);
        } on RateLimited {
          // Keep what this file already found before handing the run back.
          if (changed) await _write(file, catalog);
          rethrow;
        } on RequestFailed catch (error) {
          // A song whose search never ran is unknown, not missing - saying
          // "not on Spotify" here would swap out a good entry over a bad
          // request, which is exactly how the first miss list came about.
          unchecked.add('${catalog['id']} · ${song['year']} · $title: $error');
          continue;
        }
        if (track == null) {
          swap.add('${catalog['id']} · ${song['year']} · $title - $artist');
          continue;
        }

        song['spotifyTrackId'] = track['id'];
        changed = true;
        resolved++;

        // The Spotify year is only a cross-check: for remasters it differs, and
        // then the card no longer matches the song.
        final released = (track['album']?['release_date'] as String?) ?? '';
        final spotifyYear = int.tryParse(released.split('-').first);
        final catalogYear = song['year'] as int;
        if (spotifyYear != null && (spotifyYear - catalogYear).abs() > 1) {
          review.add(
            '${catalog['id']} · $title: catalog $catalogYear, '
            'Spotify $spotifyYear ("${track['name']}" / '
            '${track['album']?['name']})',
          );
        }
      }

      if (changed) await _write(file, catalog);
    }

    stdout.writeln('$resolved track ids added, ${swap.length} without a song.');
    if (swap.isNotEmpty) {
      stdout.writeln(
        '\nNot on Spotify - swap each for another entry of the same year '
        '(CLAUDE.md):',
      );
      for (final line in swap) {
        stdout.writeln('  $line');
      }
    }
    if (unchecked.isNotEmpty) {
      stdout.writeln('\nCould not be looked up - run again, do NOT swap:');
      for (final line in unchecked) {
        stdout.writeln('  $line');
      }
    }
    if (review.isNotEmpty) {
      stdout.writeln('\nCheck the year by hand:');
      for (final line in review) {
        stdout.writeln('  $line');
      }
    }
  } on RateLimited catch (error) {
    stderr.writeln('\n$error');
    stderr.writeln(
      'Everything found up to here has been written to the files.',
    );
    exit(2);
  }
}
