import 'package:flutter_test/flutter_test.dart';

import '../tool/resolve_youtube_music_tracks.dart';

Map<String, dynamic> run(String text, {String? page}) => {
  'text': text,
  if (page != null)
    'navigationEndpoint': {
      'browseEndpoint': {
        'browseEndpointContextSupportedConfigs': {
          'browseEndpointContextMusicConfig': {'pageType': page},
        },
      },
    },
};

/// One row the way the search hands it back, cut down to what is looked at.
Map<String, dynamic> row(
  String title,
  List<String> artists, {
  String? videoId = 'abcdefghijk',
  String album = 'Album',
  bool greyedOut = false,
}) => {
  'musicResponsiveListItemRenderer': {
    'playlistItemData': ?(videoId == null ? null : {'videoId': videoId}),
    if (greyedOut)
      'musicItemRendererDisplayPolicy':
          'MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT',
    'flexColumns': [
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [run(title)],
          },
        },
      },
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [
              for (final (index, artist) in artists.indexed) ...[
                if (index > 0) run(' & '),
                run(artist, page: 'MUSIC_PAGE_TYPE_ARTIST'),
              ],
              run(' • '),
              run(album, page: 'MUSIC_PAGE_TYPE_ALBUM'),
              run(' • '),
              run('2:56'),
            ],
          },
        },
      },
    ],
  },
};

Map<String, dynamic> response(List<Map<String, dynamic>> rows) => {
  'contents': {
    'tabbedSearchResultsRenderer': {
      'tabs': [
        {
          'content': {
            'sectionListRenderer': {
              'contents': [
                {
                  'musicShelfRenderer': {'contents': rows},
                },
              ],
            },
          },
        },
      ],
    },
  },
};

YouTubeSong song(String title, {String album = 'Album'}) => YouTubeSong(
  videoId: 'abcdefghijk',
  title: title,
  artists: const ['Lena'],
  album: album,
);

void main() {
  test('a row gives id, title, every artist and the album', () {
    final songs = parseSearch(
      response([
        row(
          'Satellite',
          ['Lena'],
          videoId: '93ugDwiBVzA',
          album: 'My Cassette Player',
        ),
        row('Ding-a-dong', ['Teach-In', 'Getty Kaspers']),
      ]),
    );

    expect(songs, hasLength(2));
    expect(songs.first.videoId, '93ugDwiBVzA');
    expect(songs.first.title, 'Satellite');
    expect(songs.first.artists, ['Lena']);
    expect(songs.first.album, 'My Cassette Player');
    expect(songs.last.artists, ['Teach-In', 'Getty Kaspers']);
  });

  test('a row that cannot be played is no candidate', () {
    final songs = parseSearch(
      response([
        row('Without id', ['Lena'], videoId: null),
        row('Not in Germany', ['Lena'], greyedOut: true),
      ]),
    );

    expect(songs, isEmpty);
  });

  test('a live cut is not the recording, a song called Live is', () {
    expect(isTheRecording(song('Satellite (Live)')), isFalse);
    expect(isTheRecording(song('Satellite - Live at Oslo')), isFalse);
    expect(
      isTheRecording(song('Satellite', album: 'Good News (Live)')),
      isFalse,
    );
    expect(isTheRecording(song('Live Is Life')), isTrue);
    expect(isTheRecording(song('Satellite')), isTrue);
  });

  test('a second take of the artist is not the recording', () {
    expect(isTheRecording(song('Tattoo (Acoustic)')), isFalse);
    expect(isTheRecording(song('Satellite (Sped Up)')), isFalse);
    expect(isTheRecording(song('Satellite', album: 'Karaoke Hits')), isFalse);
  });

  test('the id goes in next to the Spotify one', () {
    final entry = withVideoId({
      'year': 2010,
      'title': 'Satellite',
      'spotifyTrackId': 'x' * 22,
      'tier': 1,
    }, '93ugDwiBVzA');

    expect(entry.keys, [
      'year',
      'title',
      'spotifyTrackId',
      'youtubeVideoId',
      'tier',
    ]);
  });
}
