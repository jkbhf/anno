import 'package:anno/data/year_database.dart';
import 'package:anno/game/game_controller.dart';
import 'package:anno/models/player.dart';
import 'package:anno/models/song.dart';
import 'package:anno/models/song_category.dart';
import 'package:anno/music/lyrics.dart';
import 'package:anno/music/music_service.dart';
import 'package:anno/music/song_launcher.dart';
import 'package:anno/music/spotify_session.dart';
import 'package:anno/sync/game_broadcast.dart';
import 'package:anno/sync/mirror_game.dart';
import 'package:anno/sync/sync_messages.dart';
import 'package:anno/sync/tv_link.dart';
import 'package:anno/ui/app_scope.dart';
import 'package:anno/ui/game_screen.dart';
import 'package:anno/ui/lyrics_sheet.dart';
import 'package:anno/ui/scanner_screen.dart';
import 'package:anno/ui/theme.dart';
import 'package:anno/ui/tv_screen.dart';
import 'package:anno_relay/anno_relay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const card = 'https://play-the-music.com/de/year/182ca01194a98f0b';

final esc = SongCategory(
  id: 'esc',
  name: 'ESC',
  description: '',
  songs: const [
    Song(
      title: 'My Number One',
      artist: 'Helena Paparizou',
      year: 2005,
      spotifyTrackId: '3gSnnBf9fulK2fizqxmsXn',
      country: 'Greece',
      place: 1,
    ),
  ],
);

class _InTab implements SongLauncher {
  const _InTab();

  @override
  Future<LaunchResult> open(Song song) async => const LaunchResult.inTab();
}

class _Words implements LyricsSource {
  @override
  Future<Lyrics?> find(Song song, {Duration? duration}) async =>
      Lyrics.fromLrc('[00:00.00] First\n[00:40.00] Second');
}

GameController buildGame() => GameController(
  players: [
    GamePlayer(name: 'Anthony'),
    GamePlayer(name: 'Jakob'),
  ],
  categories: [esc],
  years: YearDatabase.inMemory(defaults: const {'182ca01194a98f0b': 2005}),
  launcher: const _InTab(),
);

/// A session in the middle of a song, so there is a position to send.
class _Playing extends NoSpotifySession {
  @override
  SpotifyConnection get connection => SpotifyConnection.ready;

  @override
  bool get isPlaying => true;

  @override
  Duration get position => const Duration(seconds: 42);

  @override
  Duration get duration => const Duration(seconds: 200);
}

/// A session that notes whether it was taken off the account as a speaker.
class _Device extends NoSpotifySession {
  bool released = false;

  @override
  Future<void> releaseDevice() async => released = true;
}

Widget wrapTv(TvLink link, YearDatabase years, {SpotifySession? spotify}) =>
    AppScope(
      years: years,
      categories: [esc],
      spotify: spotify ?? NoSpotifySession(),
      link: link,
      service: ValueNotifier(MusicService.spotify),
      child: MaterialApp(
        theme: buildTheme(),
        home: TvScreen(link: link),
      ),
    );

Widget wrapRemote(GameController game, TvLink link, SpotifySession spotify) =>
    AppScope(
      years: game.years,
      categories: game.categories,
      spotify: spotify,
      link: link,
      service: ValueNotifier(game.service),
      child: MaterialApp(
        theme: buildTheme(),
        home: GameScreen(controller: game, lyrics: _Words()),
      ),
    );

/// Closes the camera a new game opens by itself: on a phone that is the
/// scanner page over the screen, and these tests are about what is under it.
Future<void> closeAutoScanner(WidgetTester tester) async {
  final scanner = find.byType(ScannerScreen);
  if (scanner.evaluate().isEmpty) return;
  Navigator.of(tester.element(scanner)).pop();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the whole way across', () {
    late RelayServer relay;
    late String url;

    setUp(() async {
      relay = RelayServer();
      await relay.start(port: 0);
      url = 'ws://127.0.0.1:${relay.port}/';
    });

    tearDown(() async => relay.stop());

    Future<void> until(bool Function() done) async {
      for (var waited = 0; waited < 400; waited++) {
        if (done()) return;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('never happened');
    }

    test('the round the phone plays turns up on the screen', () async {
      final screenLink = TvLink(url: url);
      final phoneLink = TvLink(url: url);
      addTearDown(screenLink.dispose);
      addTearDown(phoneLink.dispose);

      final mirror = MirrorGame.empty(YearDatabase.inMemory());
      final session = MirrorSession();
      addTearDown(mirror.dispose);
      addTearDown(session.dispose);
      screenLink.onMessage = (message) => switch (message) {
        GameSnapshot() => mirror.apply(message),
        PlaybackTick() => session.apply(message),
        RemoteCommand() => null,
      };

      await screenLink.host();
      await until(() => screenLink.code != null);

      final game = buildGame();
      addTearDown(game.dispose);
      final spotify = _Playing();
      final broadcast = GameBroadcast(
        link: phoneLink,
        game: game,
        session: spotify,
        snapshot: () => GameSnapshot.of(
          game,
          showScores: true,
          sessionReady: true,
          syncMode: false,
          hasLyrics: true,
        ),
      );
      addTearDown(broadcast.stop);
      broadcast.start();

      await phoneLink.join(screenLink.code!);
      await until(() => phoneLink.isPaired);

      game.scan(card);
      await game.startPlayback();
      await until(() => mirror.currentSong != null);

      expect(mirror.phase, RoundPhase.playing);
      expect(mirror.currentYear, 2005);
      expect(mirror.currentSong?.title, 'My Number One');
      expect(mirror.currentCategory?.name, 'ESC');
      expect(mirror.players.map((p) => p.name), ['Anthony', 'Jakob']);
      expect(mirror.playingInApp, isTrue);

      // The clock came with it, and runs on the screen's own time.
      await until(() => session.duration > Duration.zero);
      expect(session.duration, const Duration(seconds: 200));
      expect(session.position.inSeconds, greaterThanOrEqualTo(42));
      expect(session.isPlaying, isTrue);

      // The reveal is the phone's, and the screen follows it.
      game.reveal();
      await until(() => mirror.isRevealed);

      // So are the points.
      game.addPoint(game.players.first);
      await until(() => mirror.players.first.score == 1);

      // And a screen that turns up later is told everything.
      final second = TvLink(url: url);
      addTearDown(second.dispose);
      final late = MirrorGame.empty(YearDatabase.inMemory());
      addTearDown(late.dispose);
      second.onMessage = (message) {
        if (message is GameSnapshot) late.apply(message);
      };
      await second.join(screenLink.code!);
      await until(() => late.currentSong != null);
      expect(late.currentYear, 2005);
      expect(late.players.first.score, 1);
    });
  });

  group('the screen', () {
    testWidgets('shows the code until a phone is on it', (tester) async {
      final link = TvLink.paired(role: LinkRole.screen, code: 'QRS789');
      // Not paired yet: the code is the whole screen.
      final waiting = TvLink(url: '');
      addTearDown(link.dispose);
      addTearDown(waiting.dispose);

      await tester.pumpWidget(wrapTv(link, YearDatabase.inMemory()));
      await tester.pumpAndSettle();

      // Paired but nothing has arrived: still the code, and a word that it
      // is waiting for the first card.
      expect(find.text('Q R S 7 8 9'), findsOne);
      expect(find.textContaining('Waiting for the first card'), findsOne);
      expect(find.byType(WideRound), findsNothing);
    });

    testWidgets('the code screen has the way back out', (tester) async {
      final link = TvLink.paired(role: LinkRole.screen, code: 'QRS789');
      addTearDown(link.dispose);

      await tester.pumpWidget(
        AppScope(
          years: YearDatabase.inMemory(),
          categories: [esc],
          spotify: NoSpotifySession(),
          link: link,
          service: ValueNotifier(MusicService.spotify),
          child: MaterialApp(
            theme: buildTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TvScreen(link: link),
                    ),
                  ),
                  child: const Text('Be the television'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Be the television'));
      await tester.pumpAndSettle();
      expect(find.text('Q R S 7 8 9'), findsOne);

      // This screen has no app bar to carry a back arrow, so the button is
      // under the code.
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Q R S 7 8 9'), findsNothing);
      expect(find.text('Be the television'), findsOne);
    });

    testWidgets('draws the round, and no camera box', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final link = TvLink.paired(role: LinkRole.screen);
      addTearDown(link.dispose);
      await tester.pumpWidget(wrapTv(link, YearDatabase.inMemory()));
      await tester.pumpAndSettle();

      link.onMessage!(
        GameSnapshot(
          phase: RoundPhase.playing,
          players: const [(name: 'Anthony', score: 2)],
          targetScore: 10,
          showScores: true,
          year: 2005,
          title: 'My Number One',
          artist: 'Helena Paparizou',
          deck: 'ESC',
          country: 'Greece',
          place: 1,
          playingInApp: true,
          sessionReady: true,
          hasLyrics: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WideRound), findsOne);
      // The room's half: the words and the scores.
      expect(find.byType(LyricsView), findsOne);
      expect(find.text('Anthony'), findsOne);
      // The column's half, as a label rather than as a button anybody here
      // can press - and the lens is on the phone.
      expect(find.text('Reveal the year'), findsOne);
      expect(find.byType(ScannerView), findsNothing);

      // Pressing it changes nothing: the game is on the phone.
      await tester.tap(find.byKey(revealInColumnKey));
      await tester.pumpAndSettle();
      expect(find.text('Reveal the year'), findsOne);
    });

    testWidgets('is not a speaker on the account', (tester) async {
      final link = TvLink.paired(role: LinkRole.screen, code: 'QRS789');
      addTearDown(link.dispose);
      final spotify = _Device();
      addTearDown(spotify.dispose);

      await tester.pumpWidget(
        wrapTv(link, YearDatabase.inMemory(), spotify: spotify),
      );
      await tester.pumpAndSettle();

      // The music belongs on the phone. This page runs the same app, so
      // without this it offers itself to the phone's Connect session as the
      // device to play the round on.
      expect(spotify.released, isTrue);
    });

    testWidgets('a game without cards says which range it is in', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final link = TvLink.paired(role: LinkRole.screen);
      addTearDown(link.dispose);
      await tester.pumpWidget(wrapTv(link, YearDatabase.inMemory()));
      await tester.pumpAndSettle();

      // The range and the count are the phone's: the catalogs are over
      // there, so this screen can only read what it was sent.
      link.onMessage!(
        const GameSnapshot(
          phase: RoundPhase.idle,
          players: [(name: 'Anthony', score: 0)],
          targetScore: 10,
          showScores: true,
          fromYear: 1970,
          toYear: 2026,
          playedYears: [1981, 2004],
          playableYears: [1970, 1981, 2004, 2026],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Draw a year'), findsOne);
      expect(find.text('1970 to 2026, 2 of 4 played'), findsOne);
    });

    testWidgets('the winners, and none of the buttons', (tester) async {
      final link = TvLink.paired(role: LinkRole.screen);
      addTearDown(link.dispose);
      await tester.pumpWidget(wrapTv(link, YearDatabase.inMemory()));
      await tester.pumpAndSettle();

      link.onMessage!(
        const GameSnapshot(
          phase: RoundPhase.finished,
          players: [(name: 'Anthony', score: 10), (name: 'Jakob', score: 4)],
          targetScore: 10,
          showScores: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Anthony wins'), findsOne);
      expect(find.text('Play again, same players'), findsNothing);
      expect(find.text('Back to start'), findsNothing);
    });

    testWidgets('a step from the phone moves the words and says so', (
      tester,
    ) async {
      final link = TvLink.paired(role: LinkRole.screen);
      addTearDown(link.dispose);
      await tester.pumpWidget(wrapTv(link, YearDatabase.inMemory()));
      await tester.pumpAndSettle();

      // A round first: the flash is over the words, and the words are only
      // there once there is a round to show.
      link.onMessage!(
        const GameSnapshot(
          phase: RoundPhase.playing,
          players: [(name: 'Anthony', score: 0)],
          targetScore: 10,
          showScores: true,
          year: 2005,
          title: 'My Number One',
          artist: 'Helena Paparizou',
          deck: 'ESC',
        ),
      );
      await tester.pumpAndSettle();

      link.onMessage!(const RemoteCommand(RemoteStep.wordsEarlier));
      await tester.pump();
      // The number says itself where the words are, because that is where
      // whoever pressed is looking.
      expect(find.byType(SyncFlash), findsOne);
      expect(find.textContaining('100'), findsOne);
    });

    testWidgets(
      'a step moves the column, the slot and the screen - and is kept',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final link = TvLink.paired(role: LinkRole.screen);
        addTearDown(link.dispose);
        await tester.pumpWidget(wrapTv(link, YearDatabase.inMemory()));
        await tester.pumpAndSettle();

        link.onMessage!(const RemoteCommand(RemoteStep.columnWider));
        link.onMessage!(const RemoteCommand(RemoteStep.slotTaller));
        link.onMessage!(const RemoteCommand(RemoteStep.uiBigger));
        await tester.pumpAndSettle();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getDouble('column.share'), greaterThan(0.28));
        expect(prefs.getDouble('column.slot'), greaterThan(0.36));
        expect(prefs.getDouble('ui.scale'), greaterThan(1));
      },
    );
  });

  group('the remote', () {
    testWidgets('is the controls and nothing the room reads', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final game = buildGame();
      addTearDown(game.dispose);
      final link = TvLink.paired(role: LinkRole.remote);
      addTearDown(link.dispose);

      await tester.pumpWidget(wrapRemote(game, link, _Playing()));
      await tester.pumpAndSettle();
      await closeAutoScanner(tester);

      game.scan(card);
      await game.startPlayback();
      await tester.pumpAndSettle();

      // The one action of the round, big.
      expect(find.text('Reveal the year'), findsOne);
      // The words are on the wall, and so is the year.
      expect(find.byType(LyricsView), findsNothing);
      expect(find.text('Lyrics'), findsNothing);

      await tester.tap(find.byKey(revealInColumnKey));
      await tester.pumpAndSettle();
      await closeAutoScanner(tester);
      expect(game.isRevealed, isTrue);
      // Now the phone is where the points are handed out.
      expect(find.text('Anthony'), findsOne);
      expect(find.text('The next card'), findsOne);
    });

    testWidgets('the menu steps the words on the screen, not here', (
      tester,
    ) async {
      final game = buildGame();
      addTearDown(game.dispose);
      final sent = <SyncMessage>[];
      final link = TvLink.paired(role: LinkRole.remote, onSend: sent.add);
      addTearDown(link.dispose);

      await tester.pumpWidget(wrapRemote(game, link, _Playing()));
      await tester.pumpAndSettle();
      await closeAutoScanner(tester);

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bigger words'));
      await tester.pumpAndSettle();

      final steps = sent.whereType<RemoteCommand>().toList();
      expect(steps.single.step, RemoteStep.wordsBigger);
      // Nothing was written here: the size belongs to the screen showing the
      // words, and this phone is not it.
      expect(
        SharedPreferences.getInstance().then(
          (prefs) => prefs.getDouble('lyrics.scale'),
        ),
        completion(isNull),
      );
    });

    testWidgets('the sync arrows send a direction, never a number', (
      tester,
    ) async {
      final game = buildGame();
      addTearDown(game.dispose);
      final sent = <SyncMessage>[];
      final link = TvLink.paired(role: LinkRole.remote, onSend: sent.add);
      addTearDown(link.dispose);

      await tester.pumpWidget(wrapRemote(game, link, _Playing()));
      await tester.pumpAndSettle();
      await closeAutoScanner(tester);
      game.scan(card);
      await game.startPlayback();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync the words'));
      await tester.pumpAndSettle();

      // No number on the remote: it cannot know the screen's, and a wrong
      // one would be worse than none.
      expect(find.text('on the screen'), findsOne);

      await tester.tap(find.byTooltip('The words earlier'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('The words later'));
      await tester.pumpAndSettle();

      final steps = sent.whereType<RemoteCommand>().map((c) => c.step);
      expect(steps, [RemoteStep.wordsEarlier, RemoteStep.wordsLater]);
    });

    testWidgets('steps the television\'s own handles, never a drag here', (
      tester,
    ) async {
      final game = buildGame();
      addTearDown(game.dispose);
      final sent = <SyncMessage>[];
      final link = TvLink.paired(role: LinkRole.remote, onSend: sent.add);
      addTearDown(link.dispose);

      await tester.pumpWidget(wrapRemote(game, link, _Playing()));
      await tester.pumpAndSettle();
      await closeAutoScanner(tester);

      for (final label in [
        'Wider column',
        'Narrower column',
        'Taller reveal',
        'Shorter reveal',
        'Bigger screen',
        'Smaller screen',
      ]) {
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      final steps = sent.whereType<RemoteCommand>().map((c) => c.step);
      expect(steps, [
        RemoteStep.columnWider,
        RemoteStep.columnNarrower,
        RemoteStep.slotTaller,
        RemoteStep.slotShorter,
        RemoteStep.uiBigger,
        RemoteStep.uiSmaller,
      ]);
    });
  });
}
