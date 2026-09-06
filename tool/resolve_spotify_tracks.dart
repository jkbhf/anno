// Fills in missing Spotify track ids in the song catalogs under assets/songs/.
//
//   export SPOTIFY_CLIENT_ID=...
//   export SPOTIFY_CLIENT_SECRET=...
//   dart run tool/resolve_spotify_tracks.dart [assets/songs/esc.json ...]
//
// Uses the client credentials flow: that is enough for the search and needs no
// logged in user. Songs that already carry an id are left alone. At the end the
// script lists every hit whose Spotify year differs from the catalog - usually
// a remaster, which would put the wrong year on the card.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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

/// Best hit for title and artist, or null when the search comes back empty.
Future<Map<String, dynamic>?> searchTrack(
  String token,
  String title,
  String artist,
) async {
  final query = Uri.encodeQueryComponent('track:$title artist:$artist');
  final response = await http.get(
    Uri.parse('https://api.spotify.com/v1/search?q=$query&type=track&limit=5'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (response.statusCode != 200) {
    stderr.writeln('Search failed (${response.statusCode}): $title');
    return null;
  }
  final items = (jsonDecode(response.body)['tracks']['items'] as List)
      .cast<Map<String, dynamic>>();
  return items.isEmpty ? null : items.first;
}

Future<void> main(List<String> args) async {
  final id = Platform.environment['SPOTIFY_CLIENT_ID'];
  final secret = Platform.environment['SPOTIFY_CLIENT_SECRET'];
  if (id == null || secret == null) {
    stderr.writeln('Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET.');
    exit(1);
  }

  final files = args.isNotEmpty
      ? args.map(File.new).toList()
      : Directory('assets/songs')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList();

  final token = await fetchToken(id, secret);
  final review = <String>[];
  var resolved = 0;
  var missing = 0;

  for (final file in files) {
    final catalog = jsonDecode(await file.readAsString())
        as Map<String, dynamic>;
    final songs = (catalog['songs'] as List).cast<Map<String, dynamic>>();
    var changed = false;

    for (final song in songs) {
      final existing = song['spotifyTrackId'];
      if (existing is String && existing.isNotEmpty) continue;

      final title = song['title'] as String;
      final artist = song['artist'] as String;
      final track = await searchTrack(token, title, artist);
      if (track == null) {
        missing++;
        review.add('${catalog['id']} · $title - $artist: no hit');
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

    if (changed) {
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(catalog)}\n',
      );
      stdout.writeln('${file.path} updated.');
    }
  }

  stdout.writeln('$resolved track ids added, $missing without a hit.');
  if (review.isNotEmpty) {
    stdout.writeln('\nCheck by hand:');
    for (final line in review) {
      stdout.writeln('  $line');
    }
  }
}
