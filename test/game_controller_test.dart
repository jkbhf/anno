import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:anno/data/year_database.dart';
import 'package:anno/game/game_controller.dart';
import 'package:anno/models/player.dart';
import 'package:anno/models/song.dart';
import 'package:anno/models/song_category.dart';
import 'package:anno/music/music_service.dart';
import 'package:anno/music/song_launcher.dart';

class FakeLauncher implements SongLauncher {
  FakeLauncher({this.opened = true, this.inApp = false});

  final bool opened;
  final bool inApp;
  final List<Song> played = [];

  @override
  Future<LaunchResult> open(Song song) async {
    played.add(song);
    return LaunchResult(
      opened: opened,
      message: opened ? null : 'no Spotify',
      inApp: inApp,
    );
  }
}

const card2005 = 'https://play-the-music.com/de/year/182ca01194a98f0b';

/// Answers only when the test says so - a launch still on its way.
class PendingLauncher implements SongLauncher {
  final Completer<LaunchResult> _answer = Completer();

  void answer(LaunchResult result) => _answer.complete(result);

  @override
  Future<LaunchResult> open(Song song) => _answer.future;
}

class ThrowingLauncher implements SongLauncher {
  @override
  Future<LaunchResult> open(Song song) async => throw StateError('broken');
}

GameController buildGameWith(SongLauncher launcher) => GameController(
  players: [GamePlayer(name: 'Anna')],
  categories: [buildCategory()],
  years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
  launcher: launcher,
);

/// One whole round on [card2005]: the song goes out, the year comes up, on to
/// the next. That is what counts a song as played - a closed countdown is not.
Future<Song> playRound(GameController game) async {
  game.scan(card2005);
  final song = game.currentSong!;
  await game.startPlayback();
  game.reveal();
  game.nextRound();
  return song;
}

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

/// A deck with one song in each of [years].
SongCategory deckOfYears(Iterable<int> years) => SongCategory(
  id: 'esc',
  name: 'ESC',
  description: '',
  songs: [
    for (final year in years)
      Song(
        title: 'Song $year',
        artist: 'Someone',
        year: year,
        spotifyTrackId: 'id$year',
      ),
  ],
);

/// A game that draws its own years, see `GameController.withoutCards`.
GameController buildCardlessGame({
  required int from,
  required int to,
  SongCategory? category,
  Iterable<int> playedYears = const [],
  Random? random,
}) => GameController(
  players: [GamePlayer(name: 'Anna')],
  categories: [
    category ?? deckOfYears([for (var y = from; y <= to; y++) y]),
  ],
  years: YearDatabase.inMemory(),
  launcher: FakeLauncher(),
  fromYear: from,
  toYear: to,
  playedYears: playedYears,
  random: random,
);

void main() {
  group('without cards', () {
    test('every year of the range comes once before any comes again', () async {
      final game = buildCardlessGame(from: 2001, to: 2005);
      expect(game.withoutCards, isTrue);

      final drawn = <int>[];
      for (var round = 0; round < 5; round++) {
        final next = game.nextYear()!;
        expect(next.startedOver, isFalse);
        drawn.add(next.year);
        // A year only counts once the song has gone out, so the round has to
        // be played rather than only drawn.
        game.scan('${next.year}');
        await game.startPlayback();
        game.reveal();
        game.nextRound();
      }

      expect(drawn.toSet().length, 5, reason: 'no year twice');
      expect(drawn.toSet(), {2001, 2002, 2003, 2004, 2005});

      // The sixth has nothing left, so the pass starts over and says so.
      final again = game.nextYear()!;
      expect(again.startedOver, isTrue);
      expect(game.playedYears, isEmpty);
    });

    test('a year no deck has a song for is never drawn', () {
      // 2003 is the hole: the range spans it, the deck does not.
      final game = buildCardlessGame(
        from: 2001,
        to: 2005,
        category: deckOfYears([2001, 2002, 2004, 2005]),
      );

      expect(game.playableYears, [2001, 2002, 2004, 2005]);
      for (var round = 0; round < 20; round++) {
        expect(game.nextYear()!.year, isNot(2003));
      }
    });

    test('a range without a single song draws nothing', () {
      final game = buildCardlessGame(
        from: 1960,
        to: 1965,
        category: deckOfYears([2001]),
      );

      expect(game.playableYears, isEmpty);
      expect(game.nextYear(), isNull);
    });

    test('the years it has drawn are part of the saved game', () async {
      final game = buildCardlessGame(
        from: 2001,
        to: 2005,
        playedYears: const [2002],
      );

      game.scan('2004');
      await game.startPlayback();

      expect(game.playedYears, {2002, 2004});
      expect(game.snapshot.playedYears, unorderedEquals([2002, 2004]));
      expect(game.snapshot.fromYear, 2001);
      expect(game.snapshot.toYear, 2005);
    });

    test('a closed countdown costs the range no year', () {
      final game = buildCardlessGame(from: 2001, to: 2005);

      game.scan('2003');
      game.cancelRound();

      expect(game.playedYears, isEmpty);
    });

    test('a game with cards has no range and draws no year', () {
      final game = buildGame();

      expect(game.withoutCards, isFalse);
      expect(game.playableYears, isEmpty);
      expect(game.nextYear(), isNull);
      expect(game.snapshot.fromYear, isNull);
      expect(game.snapshot.playedYears, isEmpty);
    });
  });

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

  test('the round follows the way the song actually went', () async {
    final game = buildGame();
    game.scan(card2005);
    await game.startPlayback();
    expect(
      game.playingInApp,
      isFalse,
      reason: 'this launcher hands the song over by link',
    );

    final inApp = buildGame(launcher: FakeLauncher(inApp: true));
    inApp.scan(card2005);
    await inApp.startPlayback();
    expect(inApp.playingInApp, isTrue);
  });

  test('an in-app round is not revealed by switching away and back', () async {
    final game = buildGame(launcher: FakeLauncher(inApp: true));
    game.scan(card2005);
    await game.startPlayback();

    // Nothing was handed over, so this is somebody glancing at a message -
    // not the way back from Spotify.
    game.onAppResumed(now: DateTime.now().add(const Duration(seconds: 20)));

    expect(game.phase, RoundPhase.playing);
    game.reveal();
    expect(game.phase, RoundPhase.revealed);
  });

  test('the next round starts out of the app again', () async {
    final game = buildGame(launcher: FakeLauncher(inApp: true));
    game.scan(card2005);
    await game.startPlayback();
    game.reveal();
    game.nextRound();

    expect(game.playingInApp, isFalse);
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

  test('a game without a limit has no winner however many points', () async {
    final game = buildGame(targetScore: 0);
    game.scan(card2005);
    await game.startPlayback();
    game.reveal();

    for (var i = 0; i < 30; i++) {
      game.addPoint(game.players.first);
    }
    game.nextRound();

    expect(game.winners, isEmpty);
    expect(game.phase, isNot(RoundPhase.finished));
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

  test('a year with several songs does not repeat right away', () async {
    final game = buildGame(
      category: buildCategory(const [
        Song(title: 'A', artist: 'X', year: 2005, spotifyTrackId: 'a'),
        Song(title: 'B', artist: 'Y', year: 2005, spotifyTrackId: 'b'),
      ]),
    );

    final first = await playRound(game);
    final second = await playRound(game);

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

  group('the service', () {
    const both = Song(
      title: 'Both',
      artist: 'X',
      year: 2005,
      spotifyTrackId: 'both',
      youtubeVideoId: 'both',
    );
    const spotifyOnly = Song(
      title: 'Spotify only',
      artist: 'X',
      year: 2005,
      spotifyTrackId: 'spotify',
    );
    const youtubeOnly = Song(
      title: 'YouTube only',
      artist: 'X',
      year: 2005,
      youtubeVideoId: 'youtube',
    );

    GameController on(MusicService service, List<Song> songs) => GameController(
      players: [GamePlayer(name: 'Anna')],
      categories: [buildCategory(songs)],
      years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
      launcher: FakeLauncher(),
      service: service,
    );

    Set<String> drawnOver(GameController game, int rounds) => {
      for (var i = 0; i < rounds; i++)
        if (game.scan(card2005) == ScanOutcome.started) game.currentSong!.title,
    };

    test('Spotify never draws a song without a Spotify id', () {
      final game = on(MusicService.spotify, [both, spotifyOnly, youtubeOnly]);

      expect(drawnOver(game, 30), {'Both', 'Spotify only'});
    });

    test('YouTube Music never draws a song without a video id', () {
      final game = on(MusicService.youtubeMusic, [
        both,
        spotifyOnly,
        youtubeOnly,
      ]);

      expect(drawnOver(game, 30), {'Both', 'YouTube only'});
    });

    test('a year with nothing the service plays is no song for the year', () {
      final game = on(MusicService.youtubeMusic, [spotifyOnly]);

      expect(game.scan(card2005), ScanOutcome.noSongForYear);
      expect(game.phase, RoundPhase.idle);
    });
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

    GameController withDecks(
      List<SongCategory> decks, {
      int seed = 1,
      Map<String, int> weights = const {},
    }) => GameController(
      players: [GamePlayer(name: 'Anna')],
      categories: decks,
      weights: weights,
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

    test('a deck comes up as often as its weight says', () {
      final game = withDecks(
        [categoryWith('esc', 'A'), categoryWith('rock', 'B')],
        weights: {'esc': 3},
      );

      var esc = 0;
      const rounds = 2000;
      for (var round = 0; round < rounds; round++) {
        game.scan(card2005);
        if (game.currentCategory!.id == 'esc') esc++;
        game.cancelRound();
      }

      // 3 against 1 is 75 % - with a fixed seed, so the margin only has to
      // cover the randomness of one run.
      expect(esc / rounds, closeTo(0.75, 0.04));
    });

    SongCategory deckOf(String id, int songs) => SongCategory(
      id: id,
      name: id,
      description: '',
      songs: [
        for (var i = 0; i < songs; i++)
          Song(
            title: '$id$i',
            artist: 'X',
            year: 2005,
            spotifyTrackId: '$id$i',
          ),
      ],
    );

    double shareOf(GameController game, String id) {
      var hits = 0;
      const rounds = 2000;
      for (var round = 0; round < rounds; round++) {
        game.scan(card2005);
        if (game.currentCategory!.id == id) hits++;
        game.cancelRound();
      }
      return hits / rounds;
    }

    test('a thin year gets a thin share', () {
      // Anthony All with weight 5 and two songs for 2000, the hit deck with
      // eleven: 5 x 2 against 1 x 10. It used to be 5 against 1, and the
      // two songs took turns on five of every six cards.
      final game = withDecks(
        [deckOf('library', 2), deckOf('hits', 11)],
        weights: {'library': 5},
      );

      expect(shareOf(game, 'library'), closeTo(0.5, 0.04));
    });

    test('songs past a full year add nothing to the share', () {
      final game = withDecks([deckOf('library', 137), deckOf('hits', 10)]);

      expect(shareOf(game, 'library'), closeTo(0.5, 0.04));
    });

    test('a missing or broken weight counts as 1', () {
      final esc = categoryWith('esc', 'A');
      final rock = categoryWith('rock', 'B');
      final game = withDecks([esc, rock], weights: {'rock': 0});

      expect(game.weightOf(esc), 1);
      expect(game.weightOf(rock), 1);
    });

    test('the weights go into the saved game', () {
      final game = withDecks(
        [categoryWith('esc', 'A'), categoryWith('rock', 'B')],
        weights: {'esc': 4},
      );

      expect(game.snapshot.categoryWeights, {'esc': 4, 'rock': 1});
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

    test('a deck that used up the year keeps its share', () {
      final hits = categoryWith('hits', 'A');
      final library = categoryWith('library', 'B');
      final game = GameController(
        players: [GamePlayer(name: 'Anna')],
        categories: [hits, library],
        years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
        launcher: FakeLauncher(),
        played: {GameController.playedKey(hits, hits.songs.single)},
        random: Random(1),
      );

      var fromHits = 0;
      const rounds = 400;
      for (var round = 0; round < rounds; round++) {
        game.scan(card2005);
        if (game.currentCategory!.id == 'hits') fromHits++;
        game.cancelRound();
      }

      // The unplayed song of the other deck used to take every round.
      expect(fromHits / rounds, closeTo(0.5, 0.08));
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

    test('the tail still comes before anything repeats', () async {
      final game = gameWith([tiered('core'), tiered('tail', tier: 2)]);

      final first = await playRound(game);
      final second = await playRound(game);

      expect(second.title, isNot(first.title));
    });
  });

  group('played songs', () {
    final songs = [
      for (final title in ['A', 'B', 'C'])
        Song(title: title, artist: 'X', year: 2005, spotifyTrackId: title),
    ];

    test('a closed countdown does not use the song up', () {
      final game = buildGame(category: buildCategory(songs));

      game.scan(card2005);
      game.cancelRound();

      expect(game.played, isEmpty);
    });

    test('a used up year starts over instead of repeating at random', () async {
      final game = buildGame(category: buildCategory(songs));

      final firstPass = [for (var i = 0; i < 3; i++) await playRound(game)];
      final secondPass = [for (var i = 0; i < 3; i++) await playRound(game)];

      expect(firstPass.map((s) => s.title).toSet(), {'A', 'B', 'C'});
      expect(secondPass.map((s) => s.title).toSet(), {'A', 'B', 'C'});
      expect(
        secondPass.first.title,
        isNot(firstPass.last.title),
        reason: 'the year does not open with the song it just ended on',
      );
    });

    test('the saved game carries what was played, a resume skips it', () async {
      final game = buildGame(category: buildCategory(songs));
      final first = await playRound(game);
      final second = await playRound(game);

      final saved = game.snapshot;
      expect(saved.played, hasLength(2));

      final resumed = GameController(
        players: saved.players,
        categories: game.categories,
        years: game.years,
        launcher: FakeLauncher(),
        played: saved.played,
      );
      final third = await playRound(resumed);

      expect(third.title, isNot(anyOf(first.title, second.title)));
    });

    test('only a song that went out is remembered for later', () async {
      final remembered = <Set<String>>[];
      final game = GameController(
        players: [GamePlayer(name: 'Anna')],
        categories: [buildCategory(songs)],
        years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
        launcher: FakeLauncher(),
        onPlayedChanged: remembered.add,
      );

      game.scan(card2005);
      game.cancelRound();
      expect(remembered, isEmpty);

      game.scan(card2005);
      await game.startPlayback();
      expect(remembered.last, {'esc|${game.currentSong!.key}'});
    });

    test('what earlier games played waits until its year is used up', () async {
      final category = buildCategory(songs);
      final remembered = <Set<String>>[];
      final game = GameController(
        players: [GamePlayer(name: 'Anna')],
        categories: [category],
        years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
        launcher: FakeLauncher(),
        played: {
          GameController.playedKey(category, songs[0]),
          GameController.playedKey(category, songs[1]),
        },
        onPlayedChanged: remembered.add,
      );

      expect((await playRound(game)).title, 'C');

      // Now the year is used up: it starts over, and the memory forgets it.
      final again = await playRound(game);
      expect(again.title, isNot('C'));
      expect(remembered.last, {GameController.playedKey(category, again)});
    });

    test('a song played in another deck waits for the fresh ones', () async {
      final other = SongCategory(
        id: 'hits',
        name: 'Hits',
        description: '',
        songs: songs,
      );
      final game = GameController(
        players: [GamePlayer(name: 'Anna')],
        categories: [buildCategory(songs)],
        years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
        launcher: FakeLauncher(),
        played: {
          GameController.playedKey(other, songs[0]),
          GameController.playedKey(other, songs[1]),
        },
      );

      expect((await playRound(game)).title, 'C');
      // Only played elsewhere is still unplayed here: no start over yet.
      expect(['A', 'B'], contains((await playRound(game)).title));
      expect(game.played, hasLength(4));
    });

    test('a rematch does not start the years over', () async {
      final game = buildGame(category: buildCategory(songs));
      final first = await playRound(game);

      game.resetScores();

      expect(game.played, {'esc|${first.key}'});
      expect((await playRound(game)).title, isNot(first.title));
    });
  });

  group('drawing again', () {
    final songs = [
      for (final title in ['A', 'B'])
        Song(title: title, artist: 'X', year: 2005, spotifyTrackId: title),
    ];

    test('swaps the song for another one of the year', () async {
      final launcher = FakeLauncher();
      final game = buildGame(
        category: buildCategory(songs),
        launcher: launcher,
      );
      game.scan(card2005);
      await game.startPlayback();
      final unknown = game.currentSong!;

      expect(game.canRedraw, isTrue);
      expect(game.redraw(), isTrue);
      expect(game.phase, RoundPhase.countdown);
      expect(game.currentSong!.title, isNot(unknown.title));

      await game.startPlayback();
      expect(launcher.played.map((s) => s.title), [
        unknown.title,
        game.currentSong!.title,
      ]);
    });

    test('never the same song again, even in a used up year', () async {
      final game = buildGame(category: buildCategory(songs));
      await playRound(game);
      await playRound(game);

      for (var i = 0; i < 10; i++) {
        game.scan(card2005);
        await game.startPlayback();
        final unknown = game.currentSong!.title;
        expect(game.redraw(), isTrue);
        expect(game.currentSong!.title, isNot(unknown));
        game.cancelRound();
      }
    });

    test('a swapped song is remembered and drawn like the tail', () async {
      final skipped = <Set<String>>[];
      final core = [
        for (final title in ['known', 'unknown'])
          Song(title: title, artist: 'X', year: 2005, spotifyTrackId: title),
      ];
      final game = GameController(
        players: [GamePlayer(name: 'Anna')],
        categories: [buildCategory(core)],
        years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
        launcher: FakeLauncher(),
        skipped: {'unknown'},
        onSkippedChanged: skipped.add,
        random: Random(3),
      );

      const rounds = 600;
      var known = 0;
      for (var round = 0; round < rounds; round++) {
        game.scan(card2005);
        if (game.currentSong!.title == 'known') known++;
        game.cancelRound();
      }
      expect(known / rounds, closeTo(0.75, 0.06));

      game.scan(card2005);
      await game.startPlayback();
      final swapped = game.currentSong!.key;
      expect(game.redraw(), isTrue);
      expect(game.skipped, {'unknown', swapped});
      // Only a song not yet remembered is news for the store.
      expect(skipped, [
        if (swapped != 'unknown') {'unknown', swapped},
      ]);
    });

    test('a swap taken back leaves no trace', () async {
      final skipped = <Set<String>>[];
      final remembered = <Set<String>>[];
      final game = GameController(
        players: [GamePlayer(name: 'Anna')],
        categories: [buildCategory(songs)],
        years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
        launcher: FakeLauncher(),
        onSkippedChanged: skipped.add,
        onPlayedChanged: remembered.add,
      );
      game.scan(card2005);
      await game.startPlayback();
      final unknown = game.currentSong!;
      expect(game.canUndoRedraw, isFalse);

      expect(game.redraw(), isTrue);
      await game.startPlayback();
      expect(game.canUndoRedraw, isTrue);

      expect(game.undoRedraw(), isTrue);
      expect(game.phase, RoundPhase.countdown);
      expect(game.currentSong, same(unknown));
      expect(game.skipped, isEmpty);
      expect(skipped.last, isEmpty);
      expect(game.played, {'esc|${unknown.key}'});
      expect(game.canUndoRedraw, isFalse);
      expect(game.undoRedraw(), isFalse, reason: 'one step back, not two');
    });

    test('there is nothing to take back in the next round', () async {
      final game = buildGame(category: buildCategory(songs));
      game.scan(card2005);
      await game.startPlayback();
      game.redraw();
      await game.startPlayback();
      game.reveal();

      expect(game.canUndoRedraw, isFalse, reason: 'the year is out');
      game.nextRound();
      game.scan(card2005);
      await game.startPlayback();
      expect(game.canUndoRedraw, isFalse);
      expect(game.undoRedraw(), isFalse);
    });

    test('a year with one song has nothing to swap in', () async {
      final game = buildGame();
      game.scan(card2005);
      await game.startPlayback();

      expect(game.canRedraw, isFalse);
      expect(game.redraw(), isFalse);
      expect(game.phase, RoundPhase.playing);
    });

    test('only while the song is playing', () {
      final game = buildGame(category: buildCategory(songs));
      game.scan(card2005);

      expect(game.redraw(), isFalse);
      expect(game.phase, RoundPhase.countdown);
    });
  });

  group('taking the last round back', () {
    test('goes back to the reveal of the round that ended the game', () async {
      var discarded = 0;
      final saves = <int>[];
      final game = GameController(
        players: [
          GamePlayer(name: 'Anna'),
          GamePlayer(name: 'Ben'),
        ],
        categories: [buildCategory()],
        years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
        targetScore: 1,
        launcher: FakeLauncher(),
        persist: (game) async => saves.add(game.players.first.score),
        discard: () async => discarded++,
      );
      game.scan(card2005);
      await game.startPlayback();
      game.reveal();
      // The double tap that should have gone to Ben.
      game.addPoint(game.players.first);
      game.nextRound();

      expect(game.phase, RoundPhase.finished);
      expect(discarded, 1, reason: 'a finished game is nothing to resume');
      expect(game.canUndoFinish, isTrue);

      game.undoFinish();

      expect(game.phase, RoundPhase.revealed);
      expect(game.currentSong?.title, 'My Number One');
      expect(game.currentYear, 2005);
      expect(saves.last, 1, reason: 'saved again, so it can be resumed');
      expect(game.canUndoFinish, isFalse);

      game.removePoint(game.players.first);
      game.addPoint(game.players.last);
      game.nextRound();
      expect(game.winners.single.name, 'Ben');
    });

    test('a rematch has nothing to take back', () async {
      final game = buildGame(targetScore: 1);
      game.scan(card2005);
      await game.startPlayback();
      game.reveal();
      game.addPoint(game.players.first);
      game.nextRound();

      game.resetScores();

      expect(game.canUndoFinish, isFalse);
      game.undoFinish();
      expect(game.phase, RoundPhase.idle);
    });
  });

  group('launches that answer late', () {
    test('a round reset during the launch stays reset, and quiet', () async {
      final launcher = PendingLauncher();
      var stops = 0;
      final game = GameController(
        players: [GamePlayer(name: 'Anna')],
        categories: [buildCategory()],
        years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
        launcher: launcher,
        stopMusic: () async => stops++,
      );
      game.scan(card2005);
      final launch = game.startPlayback();

      game.resetScores();
      launcher.answer(const LaunchResult(opened: false));
      await launch;

      expect(game.phase, RoundPhase.idle, reason: 'no reveal of year 0');
      expect(stops, 0, reason: 'nothing played here');
    });

    test('a song that started in the tab after all is stopped', () async {
      final launcher = PendingLauncher();
      var stops = 0;
      final game = GameController(
        players: [GamePlayer(name: 'Anna')],
        categories: [buildCategory()],
        years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
        launcher: launcher,
        stopMusic: () async => stops++,
      );
      game.scan(card2005);
      final launch = game.startPlayback();

      game.cancelRound();
      launcher.answer(const LaunchResult.inTab());
      await launch;

      expect(stops, 1);
      expect(game.playingInApp, isFalse);
    });

    test('a disposed game takes a late answer without complaint', () async {
      final launcher = PendingLauncher();
      final game = buildGameWith(launcher);
      game.scan(card2005);
      final launch = game.startPlayback();

      game.dispose();
      launcher.answer(const LaunchResult.ok());
      await launch;
    });

    test('coming back while the launch is out reveals nothing', () async {
      final launcher = PendingLauncher();
      final game = buildGameWith(launcher);
      game.scan(card2005);
      final launch = game.startPlayback();

      game.onAppResumed(now: DateTime.now().add(const Duration(seconds: 20)));
      expect(game.phase, RoundPhase.playing);

      launcher.answer(const LaunchResult.inTab());
      await launch;
      expect(game.playingInApp, isTrue);
    });

    test('a launcher that throws ends in the reveal, not stuck', () async {
      final game = buildGameWith(ThrowingLauncher());
      game.scan(card2005);

      await game.startPlayback();

      expect(game.phase, RoundPhase.revealed);
      expect(game.launchMessage, isNotNull);
    });
  });

  group('a song the tab took and then could not play', () {
    test('turns the round into a link round', () async {
      final game = buildGame(launcher: FakeLauncher(inApp: true));
      game.scan(card2005);
      await game.startPlayback();

      game.playbackFailedInApp();

      expect(game.playingInApp, isFalse);
      expect(game.launchMessage, isNotNull);
      expect(game.phase, RoundPhase.playing);
    });

    test('opens it again by link, not through the player', () async {
      final inApp = FakeLauncher(inApp: true);
      final link = FakeLauncher();
      final game = GameController(
        players: [GamePlayer(name: 'Anna')],
        categories: [buildCategory()],
        years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
        launcher: inApp,
        linkLauncher: link,
      );
      game.scan(card2005);
      await game.startPlayback();
      game.playbackFailedInApp();

      await game.reopen();

      expect(inApp.played, hasLength(1));
      expect(link.played, hasLength(1));
      expect(game.playingInApp, isFalse);
    });
  });
}
