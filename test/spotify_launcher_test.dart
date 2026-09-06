import 'package:flutter_test/flutter_test.dart';
import 'package:anno/models/song.dart';
import 'package:anno/music/spotify_launcher.dart';

const withTrack = Song(
  title: 'Tattoo',
  artist: 'Loreen',
  year: 2023,
  spotifyTrackId: '1DmW5Ep6ywYwxc2HMT5BG6',
);

const withoutTrack = Song(
  title: 'My Number One',
  artist: 'Helena Paparizou',
  year: 2005,
);

void main() {
  test('a track id becomes a deep link into the app', () {
    expect(
      UrlSpotifyLauncher.appUri(withTrack).toString(),
      'spotify:track:1DmW5Ep6ywYwxc2HMT5BG6',
    );
  });

  test('without a track id there is no deep link', () {
    expect(UrlSpotifyLauncher.appUri(withoutTrack), isNull);
  });

  test('the web url points at the track', () {
    expect(
      UrlSpotifyLauncher.webUri(withTrack).toString(),
      'https://open.spotify.com/track/1DmW5Ep6ywYwxc2HMT5BG6',
    );
  });

  test('without a track id the web url searches for title and artist', () {
    final uri = UrlSpotifyLauncher.webUri(withoutTrack);

    expect(uri.host, 'open.spotify.com');
    expect(uri.pathSegments.first, 'search');
    expect(
      Uri.decodeComponent(uri.pathSegments.last),
      'My Number One Helena Paparizou',
    );
  });

  test('the browser only ever gets a scheme it accepts', () {
    // url_launcher knows nothing but http(s) on the web, so the web url has to
    // work there; the deep link is for Android and iOS only.
    expect(UrlSpotifyLauncher.webUri(withTrack).scheme, 'https');
    expect(UrlSpotifyLauncher.webUri(withoutTrack).scheme, 'https');
    expect(UrlSpotifyLauncher.appUri(withTrack)!.scheme, 'spotify');
  });
}
