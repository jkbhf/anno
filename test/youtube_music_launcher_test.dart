import 'package:flutter_test/flutter_test.dart';
import 'package:anno/models/song.dart';
import 'package:anno/music/music_service.dart';
import 'package:anno/music/youtube_music_launcher.dart';

const withVideo = Song(
  title: 'Satellite',
  artist: 'Lena',
  year: 2010,
  youtubeVideoId: '93ugDwiBVzA',
);

const withoutVideo = Song(
  title: 'My Number One',
  artist: 'Helena Paparizou',
  year: 2005,
);

void main() {
  test('a video id plays the song on YouTube Music', () {
    expect(
      YouTubeMusicLauncher.uri(withVideo).toString(),
      'https://music.youtube.com/watch?v=93ugDwiBVzA',
    );
  });

  test('without a video id the url searches for title and artist', () {
    final uri = YouTubeMusicLauncher.uri(withoutVideo);

    expect(uri.scheme, 'https');
    expect(uri.host, 'music.youtube.com');
    expect(uri.path, '/search');
    expect(uri.queryParameters['q'], 'My Number One Helena Paparizou');
  });

  test('a video id is read from the catalog, an empty one is none', () {
    Song read(Object? video) => Song.fromJson({
      'title': 'Satellite',
      'artist': 'Lena',
      'year': 2010,
      'youtubeVideoId': video,
    });

    expect(read('93ugDwiBVzA').youtubeVideoId, '93ugDwiBVzA');
    expect(read('').youtubeVideoId, isNull);
    expect(() => read(7), throwsFormatException);
  });

  test('a stored service name that is gone falls back to Spotify', () {
    expect(MusicService.fromName('youtubeMusic'), MusicService.youtubeMusic);
    expect(MusicService.fromName('deezer'), MusicService.spotify);
    expect(MusicService.fromName(null), MusicService.spotify);
  });
}
