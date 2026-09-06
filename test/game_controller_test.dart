import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:anno/data/year_database.dart';
import 'package:anno/game/game_controller.dart';
import 'package:anno/models/player.dart';
import 'package:anno/models/song.dart';
import 'package:anno/models/song_category.dart';
import 'package:anno/music/spotify_launcher.dart';

class FakeLauncher implements SpotifyLauncher {
  FakeLauncher({this.opened = true});

  final bool opened;
  final List<Song> played = [];

  @override
  Future<SpotifyLaunchResult> open(Song song) async {
    played.add(song);
    return SpotifyLaunchResult(
      opened: opened,
      message: opened ? null : 'no Spotify',
    );
  }
}

const card2005 = 'https://play-the-music.com/de/year/182ca01194a98f0b';

SongCategory buildCategory([List<Song>? songs]) => SongCategory(
  id: 'esc',
  name: 'ESC',
  description: '',
  songs:
      songs ??
      const [
        Song(
          title: 'My Number One',
          artist: 'Helena Paparizou',
          year: 2005,
          spotifyTrackId: '3gSnnBf9fulK2fizqxmsXn',
        ),
      ],
);

GameController buildGame({
  SongCategory? category,
  FakeLauncher? launcher,
  int targetScore = 10,
  List<String> names = const ['Anna', 'Ben'],
}) => GameController(
  players: [for (final name in names) GamePlayer(name: name)],
  categories: [category ?? buildCategory()],
  years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
  targetScore: targetScore,
  launcher: launcher ?? FakeLauncher(),
);

void main() {
  test('a known code starts the countdown', () {
    final game = buildGame();

    expect(game.scan(card2005), ScanOutcome.started);
    expect(game.phase, RoundPhase.countdown);
    expect(game.currentYear, 2005);
    expect(game.currentSong?.title, 'My Number One');
  });

  test('an unknown code reveals nothing', () {
    final game = buildGame();

    expect(
      game.scan('https://play-the-music.com/de/year/unknown'),
      ScanOutcome.unknownCode,
    );
    expect(game.phase, RoundPhase.idle);
    expect(game.lastScannedCode, 'https://play-the-music.com/de/year/unknown');
  });

  test('a year without a song in the category reports the year', () {
    final game = buildGame(category: buildCategory(const []));

    expect(game.scan(card2005), ScanOutcome.noSongForYear);
    expect(game.currentYear, 2005);
    expect(game.currentSong, isNull);
    expect(game.phase, RoundPhase.idle);
  });

  test(
    'Spotify takes over, the year stays hidden until the app returns',
    () async {
      final launcher = FakeLauncher();
      final game = buildGame(launcher: launcher);
      game.scan(card2005);

      await game.startPlayback();

      expect(game.phase, RoundPhase.playing);
      expect(launcher.played.single.title, 'My Number One');
      expect(game.isRevealed, isFalse);
    },
  );

  test('an immediate resumed does not reveal yet', () async {
    final game = buildGame();
    game.scan(card2005);
    await game.startPlayback();

    game.onAppResumed(now: DateTime.now());
    expect(game.phase, RoundPhase.playing);

    game.onAppResumed(now: DateTime.now().add(const Duration(seconds: 20)));
    expect(game.phase, RoundPhase.revealed);
  });

  test('if Spotify fails the round reveals right away', () async {
    final game = buildGame(launcher: FakeLauncher(opened: false));
    game.scan(card2005);

    await game.startPlayback();

    expect(game.phase, RoundPhase.revealed);
    expect(game.launchMessage, 'no Spotify');
  });

  test('points are only handed out after the reveal', () async {
    final game = buildGame();
    final anna = game.players.first;

    game.addPoint(anna);
    expect(anna.score, 0);

    game.scan(card2005);
    await game.startPlayback();
    game.reveal();

    game.addPoint(anna);
    game.addPoint(anna);
    expect(anna.score, 2);

    game.removePoint(anna);
    expect(anna.score, 1);
  });

  test('scores do not go below zero', () async {
    final game = buildGame();
    game.scan(card2005);
    await game.startPlayback();
    game.reveal();

    game.removePoint(game.players.first);
    expect(game.players.first.score, 0);
  });

  test('the next round starts back at the scanner', () async {
    final game = buildGame();
    game.scan(card2005);
    await game.startPlayback();
    game.reveal();
    game.addPoint(game.players.first);

    game.nextRound();

    expect(game.phase, RoundPhase.idle);
    expect(game.currentSong, isNull);
    expect(game.currentYear, isNull);
  });

  test('the score target ends the game', () async {
    final game = buildGame(targetScore: 2);
    game.scan(card2005);
    await game.startPlayback();
    game.reveal();

    game.addPoint(game.players.first);
    game.addPoint(game.players.first);
    expect(game.phase, RoundPhase.revealed, reason: 'points stay correctable');

    game.nextRound();

    expect(game.phase, RoundPhase.finished);
    expect(game.winners.single.name, 'Anna');
  });

  test('a tie means both win', () async {
    final game = buildGame(targetScore: 1);
    game.scan(card2005);
    await game.startPlayback();
    game.reveal();

    game.addPoint(game.players[0]);
    game.addPoint(game.players[1]);
    game.nextRound();

    expect(game.winners.map((p) => p.name), ['Anna', 'Ben']);
  });

  test('a year with several songs does not repeat right away', () {
    final game = buildGame(
      category: buildCategory(const [
        Song(title: 'A', artist: 'X', year: 2005, spotifyTrackId: 'a'),
        Song(title: 'B', artist: 'Y', year: 2005, spotifyTrackId: 'b'),
      ]),
    );

    game.scan(card2005);
    final first = game.currentSong!;
    game.cancelRound();
    game.scan(card2005);
    final second = game.currentSong!;

    expect(second.key, isNot(first.key));
  });

  test('resetting clears scores and the round', () async {
    final game = buildGame();
    game.scan(card2005);
    await game.startPlayback();
    game.reveal();
    game.addPoint(game.players.first);

    game.resetScores();

    expect(game.players.every((p) => p.score == 0), isTrue);
    expect(game.phase, RoundPhase.idle);
  });

  group('several categories', () {
    SongCategory categoryWith(String id, String title) => SongCategory(
      id: id,
      name: id,
      description: '',
      songs: [
        Song(title: title, artist: 'X', year: 2005, spotifyTrackId: title),
      ],
    );

    GameController withDecks(List<SongCategory> decks, {int seed = 1}) =>
        GameController(
          players: [GamePlayer(name: 'Anna')],
          categories: decks,
          years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
          launcher: FakeLauncher(),
          random: Random(seed),
        );

    test('the draw reports which deck the song came from', () {
      final game = withDecks([categoryWith('esc', 'A')]);

      expect(game.scan(card2005), ScanOutcome.started);
      expect(game.currentCategory?.id, 'esc');
      expect(game.currentSong?.title, 'A');
    });

    test('over many rounds both decks come up', () {
      final game = withDecks([
        categoryWith('esc', 'A'),
        categoryWith('rock', 'B'),
      ]);

      final seen = <String>{};
      for (var round = 0; round < 20; round++) {
        game.scan(card2005);
        seen.add(game.currentCategory!.id);
        game.cancelRound();
      }

      expect(seen, {'esc', 'rock'});
    });

    test('a deck without that year is skipped', () {
      final empty = SongCategory(
        id: 'german_songs',
        name: 'German Songs',
        description: '',
        songs: const [],
      );
      final game = withDecks([empty, categoryWith('esc', 'A')]);

      for (var round = 0; round < 10; round++) {
        expect(game.scan(card2005), ScanOutcome.started);
        expect(game.currentCategory?.id, 'esc');
        game.cancelRound();
      }
    });

    test('no deck with that year ends the round before the countdown', () {
      final game = withDecks([
        SongCategory(id: 'esc', name: 'esc', description: '', songs: const []),
      ]);

      expect(game.scan(card2005), ScanOutcome.noSongForYear);
      expect(game.currentCategory, isNull);
    });

    test('the fresh song of the other deck beats a repeat of the first', () {
      final game = withDecks([
        categoryWith('esc', 'A'),
        categoryWith('rock', 'B'),
      ]);

      game.scan(card2005);
      final first = game.currentCategory!.id;
      game.cancelRound();

      game.scan(card2005);
      expect(game.currentCategory!.id, isNot(first));
    });
  });

  group('contest entries', () {
    test('country and rank survive the catalog', () {
      const song = Song(
        title: 'My Number One',
        artist: 'Helena Paparizou',
        year: 2005,
        country: 'Greece',
        place: 1,
      );

      expect(song.isContestEntry, isTrue);
      expect(song.country, 'Greece');
      expect(song.placeOrdinal, '1st');
    });

    test('a plain song carries no contest facts', () {
      const song = Song(title: 'A', artist: 'X', year: 1999);

      expect(song.isContestEntry, isFalse);
      expect(song.placeOrdinal, isNull);
    });

    test('ranks read as English ordinals', () {
      String? ordinal(int place) =>
          Song(title: 'A', artist: 'X', year: 1999, place: place).placeOrdinal;

      expect(ordinal(1), '1st');
      expect(ordinal(2), '2nd');
      expect(ordinal(3), '3rd');
      expect(ordinal(4), '4th');
      expect(ordinal(11), '11th');
      expect(ordinal(12), '12th');
      expect(ordinal(13), '13th');
      expect(ordinal(21), '21st');
      expect(ordinal(22), '22nd');
      expect(ordinal(23), '23rd');
      expect(ordinal(26), '26th');
    });
  });

  group('tiers', () {
    Map<String, dynamic> entry(Map<String, dynamic> extra) => {
      'year': 2005,
      'title': 'My Number One',
      'artist': 'Helena Paparizou',
      ...extra,
    };

    Song tiered(String title, {int tier = 1}) => Song(
      title: title,
      artist: 'X',
      year: 2005,
      spotifyTrackId: title,
      tier: tier,
    );

    GameController gameWith(List<Song> songs, {int seed = 7}) => GameController(
      players: [GamePlayer(name: 'Anna')],
      categories: [
        SongCategory(id: 'esc', name: 'ESC', description: '', songs: songs),
      ],
      years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
      launcher: FakeLauncher(),
      random: Random(seed),
    );

    test('a song without a tier is core', () {
      expect(Song.fromJson(entry({})).tier, 1);
    });

    test('tier 1 and 2 survive the catalog', () {
      expect(Song.fromJson(entry({'tier': 1})).tier, 1);
      expect(Song.fromJson(entry({'tier': 2})).tier, 2);
    });

    test('anything else is a format error', () {
      for (final bad in <Object>[0, 3, -1, '1', 1.5, 1.0]) {
        expect(
          () => Song.fromJson(entry({'tier': bad})),
          throwsFormatException,
          reason: 'tier: $bad',
        );
      }
    });

    test('the core of a year comes up about three times as often', () {
      final game = gameWith([tiered('core'), tiered('tail', tier: 2)]);

      const rounds = 600;
      var core = 0;
      for (var round = 0; round < rounds; round++) {
        game.scan(card2005);
        if (game.currentSong!.title == 'core') core++;
        game.cancelRound();
      }

      expect(core / rounds, closeTo(0.75, 0.06));
    });

    test('the tail still comes before anything repeats', () {
      final game = gameWith([tiered('core'), tiered('tail', tier: 2)]);

      game.scan(card2005);
      final first = game.currentSong!.title;
      game.cancelRound();

      game.scan(card2005);
      expect(game.currentSong!.title, isNot(first));
    });
  });
}
