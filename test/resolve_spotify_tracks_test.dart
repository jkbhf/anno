import 'package:flutter_test/flutter_test.dart';

import '../tool/resolve_spotify_tracks.dart';

/// The shape the Spotify search hands back, cut down to what is looked at.
Map<String, dynamic> track(
  String name,
  List<String> artists, {
  String? album,
}) => {
  'id': 'x' * 22,
  'name': name,
  'artists': [
    for (final artist in artists) {'name': artist},
  ],
  'album': {'name': album ?? name},
};

Map<String, dynamic> entry(String title, String artist) => {
  'title': title,
  'artist': artist,
  'year': 2011,
};

void main() {
  group('normalize', () {
    test('drops accents, brackets and the pressing suffix', () {
      expect(normalize('Ein bißchen Frieden'), 'ein bisschen frieden');
      expect(
        normalize('Si la vie est un cadeau (Eurovision 1983)'),
        'si la vie est un cadeau',
      );
      expect(
        normalize('Sag ihr, ich laß\' sie grüßen - Remastered 2016'),
        'sag ihr ich lass sie grussen',
      );
    });
  });

  group('artistMatches', () {
    test('a wrong artist is not a hit', () {
      // What the unquoted search used to answer for Blue's "I Can".
      expect(artistMatches('Blue', ['Adele']), isFalse);
      expect(artistMatches('Vikki', ['Vicky Leandros']), isFalse);
    });

    test('one half of a duo is enough', () {
      expect(artistMatches('Ell & Nikki', ['Ell']), isTrue);
      expect(
        artistMatches('Jahn Teigen & Anita Skorgan', ['Jahn Teigen']),
        isTrue,
      );
    });

    test('a longer credit still matches', () {
      expect(artistMatches('Max', ['Max Mutzke']), isTrue);
      expect(artistMatches('Friderika Bayer', ['Friderika']), isTrue);
    });
  });

  group('titleMatches', () {
    test('another song of the same artist is not a hit', () {
      expect(titleMatches('Chai', 'Ayelet Chen'), isFalse);
      expect(titleMatches('Amour, amour', 'Sans amour'), isFalse);
      expect(titleMatches('I Can', 'Can I Get It'), isFalse);
      // Two words apart, so not the same song however the apostrophe falls.
      expect(titleMatches('I Can', "I Can't Wait - Radio Edit"), isFalse);
    });

    test('one word of difference is still the same song', () {
      expect(
        titleMatches('Si la vie est cadeau', 'Si la vie est un cadeau'),
        isTrue,
      );
      expect(titleMatches('Serving', 'SERVING KANT'), isTrue);
      expect(
        titleMatches(
          "Heute Abend wollen wir tanzen geh'n",
          'Heute Abend Wollen Wir Tanzen Geh',
        ),
        isTrue,
      );
      expect(titleMatches("J'ai volé la vie", 'J AI VOLE LA VIE'), isTrue);
    });

    test('a title in another script is not judged by its name', () {
      expect(titleUnreadable('מילים'), isTrue);
      expect(titleUnreadable('Milim'), isFalse);
    });

    test('spelling and a suffix do not stand in the way', () {
      expect(
        titleMatches('Ein bißchen Frieden', 'Ein bisschen Frieden'),
        isTrue,
      );
      expect(
        titleMatches('Qélé, Qélé', 'Qélé Qélé (Eurovision 2008 Armenia)'),
        isTrue,
      );
    });
  });

  group('isTheRecording', () {
    test('karaoke, medleys and remixes are not the entry', () {
      expect(
        isTheRecording(track('Rock Bottom (Karaoke Version)', ['La-Le-Lu'])),
        isFalse,
      );
      expect(
        isTheRecording(track('Hit Medley (Diggi Loo Diggi Ley)', ['Herreys'])),
        isFalse,
      );
      expect(
        isTheRecording(
          track(
            'Rockefeller Street (New Nightcore) [#Rockefellerstreet Remix]',
            ['Getter Jaani'],
          ),
        ),
        isFalse,
      );
      expect(isTheRecording(track('Satellite', ['Lena'])), isTrue);
    });

    test('a live recording of the entry still counts', () {
      expect(
        isTheRecording(
          track('Tu te reconnaîtras', [
            'Anne-Marie David',
          ], album: 'Live á Charleroi'),
        ),
        isTrue,
      );
    });
  });

  group('cannotStay', () {
    test('another song under the id is cleared', () {
      expect(
        cannotStay(
          entry('Chai', 'Ofra Haza'),
          track('Ayelet Chen', ['Ofra Haza']),
        ),
        isNotNull,
      );
      expect(
        cannotStay(entry('I Can', 'Blue'), track('Can I Get It', ['Adele'])),
        isNotNull,
      );
    });

    test('a renamed artist keeps its id', () {
      // Charlotte Nilsson married into Perrelli; the song is the same one, and
      // dropping the id would cost the game a card for nothing.
      expect(
        cannotStay(
          entry('Take Me to Your Heaven', 'Charlotte Nilsson'),
          track('Take Me to Your Heaven', ['Charlotte Perrelli']),
        ),
        isNull,
      );
      expect(
        cannotStay(
          entry('Milim', 'Harel Skaat'),
          track('Milim', ['הראל סקעת']),
        ),
        isNull,
      );
      // Spotify carries the entry under its Hebrew title - unreadable here,
      // and no reason to drop a working id.
      expect(
        cannotStay(
          entry('Milim', 'Harel Skaat'),
          track('מילים', ['Harel Skaat']),
        ),
        isNull,
      );
    });

    test('an id that resolves to nothing goes', () {
      expect(cannotStay(entry('Mikado', 'Simone Drexel'), null), isNotNull);
    });
  });
}
