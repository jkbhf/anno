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

    test(
      'the fresh song of the other deck beats a repeat of the first',
      () async {
        final game = withDecks([
          categoryWith('esc', 'A'),
          categoryWith('rock', 'B'),
        ]);

        game.scan(card2005);
        final first = game.currentCategory!.id;
        await game.startPlayback();
        game.reveal();
        game.nextRound();

        game.scan(card2005);
        expect(game.currentCategory!.id, isNot(first));
      },
    );
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

    test('the songs of the last evenings come up less often', () {
      final category = SongCategory(
        id: 'esc',
        name: 'ESC',
        description: '',
        songs: [tiered('core'), tiered('tail', tier: 2)],
      );
      final game = GameController(
        players: [GamePlayer(name: 'Anna')],
        categories: [category],
        years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
        launcher: FakeLauncher(),
        random: Random(7),
        recentlyPlayed: {
          GameController.playedKey(category, category.songs.first),
        },
      );

      const rounds = 700;
      var core = 0;
      for (var round = 0; round < rounds; round++) {
        game.scan(card2005);
        if (game.currentSong!.title == 'core') core++;
        game.cancelRound();
      }

      // A recent core song weighs 3, a tail song nobody heard lately 1 x 4:
      // the tail now comes up more often than the core.
      expect(core / rounds, closeTo(3 / 7, 0.06));
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
      final remembered = <String>[];
      final game = GameController(
        players: [GamePlayer(name: 'Anna')],
        categories: [buildCategory(songs)],
        years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
        launcher: FakeLauncher(),
        onPlayed: remembered.add,
      );

      game.scan(card2005);
      game.cancelRound();
      expect(remembered, isEmpty);

      game.scan(card2005);
      await game.startPlayback();
      expect(remembered, ['esc|${game.currentSong!.key}']);
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
