import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/song.dart';

/// The Web API, as much of it as the two sessions share.
const String spotifyApiUrl = 'https://api.spotify.com/v1';

Map<String, String> spotifyHeaders(String token) => {
  'Authorization': 'Bearer $token',
  'Content-Type': 'application/json',
};

/// The body of `PUT /me/player/play` for one track and nothing after it.
String spotifyPlayBody(String uri) => jsonEncode({
  'uris': [uri],
});

/// The track to play for a catalog entry, `spotify:track:...`.
///
/// An entry that has no track id falls back to the same search the reveal
/// would otherwise send the player to by hand. Quoted like the resolver's:
/// `track:Diese Welt` unquoted searches for "Diese" alone and would play some
/// other song.
Future<String?> spotifyTrackUri(
  http.Client client,
  String token,
  Song song,
) async {
  final id = song.spotifyTrackId;
  if (id != null) return 'spotify:track:$id';

  final query = Uri.encodeQueryComponent(
    'track:"${song.title}" artist:"${song.artist}"',
  );
  try {
    final response = await client.get(
      Uri.parse('$spotifyApiUrl/search?q=$query&type=track&limit=1'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) return null;
    final items = (jsonDecode(response.body)['tracks']['items'] as List)
        .cast<Map<String, dynamic>>();
    return items.isEmpty ? null : items.first['uri'] as String;
  } on Object catch (error) {
    debugPrint('Search failed: $error');
    return null;
  }
}
