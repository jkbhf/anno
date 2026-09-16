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

  test('a mix is only the song when it was the one on the radio', () {
    expect(isTheRecording(song('What Is Love (7" Mix)')), isTrue);
    expect(isTheRecording(song('Durch den Monsun (Radio Mix)')), isTrue);
    expect(isTheRecording(song('Je T\'adore (Eurovision Mix)')), isTrue);
    expect(
      isTheRecording(
        song('Ooh Aah...Just a Little Bit (Motiv8 Extended Vocal Mix)'),
      ),
      isFalse,
    );
    expect(isTheRecording(song('Saturday Night (Nite Mix)')), isFalse);
    expect(isTheRecording(song('Anton aus Tirol (Silverjam RMX)')), isFalse);
    expect(
      isTheRecording(song('Blue (Da Ba Dee) (DJ Ponte Ice Pop Radio)')),
      isFalse,
    );
    expect(isTheRecording(song('Tattoo (Acappella)')), isFalse);
  });

  test('a remaster, a stereo mix and a guest are the recording', () {
    expect(
      isTheRecording(song('Love Me Do (Remastered 2009)'), year: 1962),
      isTrue,
    );
    expect(isTheRecording(song("Frag' den Abendwind (Stereo Mix)")), isTrue);
    expect(isTheRecording(song('Lean On (feat. DJ Snake)')), isTrue);
  });

  test('a later year in a bracket is a re-recording', () {
    expect(isTheRecording(song('MfG (2022)'), year: 1999), isFalse);
    expect(
      isTheRecording(song('O mein Papa (Version 2008)'), year: 1953),
      isFalse,
    );
    expect(
      isTheRecording(song('Looking High, High, High (1960)'), year: 1960),
      isTrue,
    );
  });

  test('a title nothing is left of is not taken', () {
    const water = YouTubeSong(
      videoId: 'abcdefghijk',
      title: 'Само Шампиони',
      artists: ['Elitsa Todorova', 'Stoyan Yankoulov'],
    );

    expect(
      isTheEntry(water, 'Water', 'Elitsa Todorova & Stoyan Yankoulov'),
      isFalse,
    );
  });

  test('a title with its dashes elsewhere is the same title', () {
    expect(sameTitle('Maschendrahtzaun', 'Maschen-Draht-Zaun'), isTrue);
    expect(sameTitle('I Can', "I Can't Wait"), isFalse);
  });

  test('a Hangul title is read by the name in its bracket', () {
    expect(sameTitle('PLAYING WITH FIRE', '불장난(Playing With Fire)'), isTrue);
    expect(sameTitle('WHISTLE', '불장난(Playing With Fire)'), isFalse);
    // A readable title keeps its bracket out of it.
    expect(sameTitle('Wild & Free', 'Satellite (Wild & Free)'), isFalse);
  });

  test('an artist nothing is left of is not taken', () {
    const cover = YouTubeSong(
      videoId: 'abcdefghijk',
      title: 'A-Ba-Ni-Bi',
      artists: ['สเตทเอ็กซ์เพรส'],
    );

    expect(
      isTheEntry(cover, 'A-Ba-Ni-Bi', 'Izhar Cohen & the Alphabeta'),
      isFalse,
    );
  });

  test('a take the catalog title names itself is the entry', () {
    expect(isTheRecording(song("Mine (Taylor's Version)")), isFalse);
    expect(
      isTheRecording(
        song("All Too Well (10 Minute Version) [Taylor's Version]"),
        title: "All Too Well (10 Minute Version) (Taylor's Version)",
      ),
      isTrue,
    );
  });

  test('a German version belongs to the German deck only', () {
    final lulu = song('Boom Bang a Bang (Deutsch Version)');
    final udo = song('Buenos Dias Argentina (Deutsche Version)');

    expect(isTheRecording(lulu, deck: 'esc'), isFalse);
    expect(isTheRecording(udo, deck: 'german_songs'), isTrue);
    expect(isTheRecording(song('Oh My! (Japanese ver.)')), isFalse);
  });

  test('a music video loses the artist in front of its title', () {
    const official = YouTubeSong(
      videoId: 'k2qgadSvNyU',
      title: 'Dua Lipa - New Rules (Official Music Video)',
      artists: ['Dua Lipa'],
    );
    const fan = YouTubeSong(
      videoId: 'Qs0VniZIs_o',
      title: 'Dua Lipa - New Rules (Lyrics)',
      artists: ['Dan Music'],
    );

    expect(
      isTheEntry(asVideo(official, 'Dua Lipa'), 'New Rules', 'Dua Lipa'),
      isTrue,
    );
    expect(
      isTheEntry(asVideo(fan, 'Dua Lipa'), 'New Rules', 'Dua Lipa'),
      isFalse,
    );
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
