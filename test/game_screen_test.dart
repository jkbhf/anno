import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:anno/sync/tv_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anno/data/column_width_store.dart';
import 'package:anno/data/lyrics_scale_store.dart';
import 'package:anno/data/slot_height_store.dart';
import 'package:anno/data/lyrics_sync_store.dart';
import 'package:anno/data/year_database.dart';
import 'package:anno/game/game_controller.dart';
import 'package:anno/models/player.dart';
import 'package:anno/models/song.dart';
import 'package:anno/models/song_category.dart';
import 'package:anno/music/lyrics.dart';
import 'package:anno/music/music_service.dart';
import 'package:anno/music/song_launcher.dart';
import 'package:anno/music/spotify_session.dart';
import 'package:anno/ui/app_scope.dart';
import 'package:anno/ui/centered_body.dart';
import 'package:anno/ui/game_screen.dart';
import 'package:anno/ui/layout.dart';
import 'package:anno/ui/lyrics_sheet.dart';
import 'package:anno/ui/scanner_screen.dart';
import 'package:anno/ui/theme.dart';

/// Hands the song over without a word - the link path, as on a phone.
class SilentLauncher implements SongLauncher {
  const SilentLauncher();

  @override
  Future<LaunchResult> open(Song song) async => const LaunchResult.ok();
}

/// The song plays in the tab, which is what a working in-app player reports.
class InTabLauncher implements SongLauncher {
  const InTabLauncher();

  @override
  Future<LaunchResult> open(Song song) async => const LaunchResult.inTab();
}

/// Plays in the tab, but only says so once the test lets it - the stretch
/// between the round screen going up and the launch coming back.
class LateInTabLauncher implements SongLauncher {
  final Completer<LaunchResult> answer = Completer();

  @override
  Future<LaunchResult> open(Song song) => answer.future;
}

const card = 'https://play-the-music.com/de/year/182ca01194a98f0b';

GameController buildGame({
  int players = 2,
  List<SongCategory>? categories,
  SongLauncher launcher = const SilentLauncher(),
  MusicService service = MusicService.spotify,
  Map<String, int> years = const {'182ca01194a98f0b': 2005},
  int? fromYear,
  int? toYear,
}) => GameController(
  players: [
    for (var i = 0; i < players; i++) GamePlayer(name: 'Player ${i + 1}'),
  ],
  categories: categories ?? [escCategory],
  years: YearDatabase.inMemory(defaults: years),
  launcher: launcher,
  service: service,
  fromYear: fromYear,
  toYear: toYear,
);

/// A deck with one song in each year from 2001 to 2004, for a game that draws
/// its own years.
final fourYears = SongCategory(
  id: 'hits',
  name: 'Hits',
  description: '',
  songs: const [
    Song(title: 'A', artist: 'X', year: 2001, spotifyTrackId: 'a'),
    Song(title: 'B', artist: 'X', year: 2002, spotifyTrackId: 'b'),
    Song(title: 'C', artist: 'X', year: 2003, spotifyTrackId: 'c'),
    Song(title: 'D', artist: 'X', year: 2004, spotifyTrackId: 'd'),
  ],
);

/// A second card, for the round after the one on [card].
const otherCard = 'https://play-the-music.com/de/year/91bd5e0e2c7a4f31';

final escCategory = SongCategory(
  id: 'esc',
  name: 'ESC',
  description: '',
  songs: const [
    Song(
      title: 'My Number One',
      artist: 'Helena Paparizou',
      year: 2005,
      spotifyTrackId: '3gSnnBf9fulK2fizqxmsXn',
      youtubeVideoId: 'abcdefghijk',
      country: 'Greece',
      place: 1,
    ),
  ],
);

/// A session that claims to be whatever the test needs.
class FakeSession extends NoSpotifySession {
  FakeSession(this.state, {this.playing = true});

  final SpotifyConnection state;
  final bool playing;

  @override
  SpotifyConnection get connection => state;

  @override
  bool get isPlaying => playing;

  @override
  Future<bool> play(Song song) async => state == SpotifyConnection.ready;
}

/// Two songs for 2005, so there is something to swap in.
final twoSongs = SongCategory(
  id: 'esc',
  name: 'ESC',
  description: '',
  songs: const [
    Song(title: 'A', artist: 'X', year: 2005, spotifyTrackId: 'a'),
    Song(title: 'B', artist: 'Y', year: 2005, spotifyTrackId: 'b'),
  ],
);

/// A ready session in the middle of a 3:20 song, that records where it is sent.
class SeekableSession extends FakeSession {
  SeekableSession() : super(SpotifyConnection.ready, playing: false);

  final List<Duration> seeks = [];

  /// How often play/pause was pressed, by finger or by key.
  int pauses = 0;

  /// Whether it says it is playing. Starts paused, like the session in most
  /// of these tests, and follows [togglePause] from there.
  bool nowPlaying = false;

  String? _playbackError;

  @override
  bool get isPlaying => nowPlaying;

  @override
  Future<void> togglePause() async {
    pauses++;
    nowPlaying = !nowPlaying;
  }

  @override
  Duration get duration => const Duration(seconds: 200);

  /// Where the player is. Settable, so a test can sit just before a line.
  Duration at = const Duration(seconds: 42);

  @override
  Duration get position => at;

  @override
  String? get playbackError => _playbackError;

  void failPlayback(String message) {
    _playbackError = message;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async => seeks.add(position);
}

/// Words for every song, timed at 0:00, 0:40 and 1:00 - the fake session
/// sits at 0:42, so the second line is the one being sung.
class FakeLyrics implements LyricsSource {
  FakeLyrics({this.lyrics});

  final Lyrics? lyrics;

  /// The recording length of every request, in order.
  final List<Duration?> asked = [];

  @override
  Future<Lyrics?> find(Song song, {Duration? duration}) async {
    asked.add(duration);
    return lyrics ??
        Lyrics.fromLrc('[00:00.00] First\n[00:40.00] Second\n[01:00.00] Third');
  }
}

Widget wrap(
  GameController game, {
  SpotifySession? spotify,
  LyricsSource? lyrics,
  CameraBuilder? camera,
}) => AppScope(
  years: game.years,
  categories: game.categories,
  spotify: spotify ?? NoSpotifySession(),
  link: TvLink(url: ''),
  service: ValueNotifier(game.service),
  child: MaterialApp(
    theme: buildTheme(),
    home: GameScreen(
      controller: game,
      lyrics: lyrics ?? FakeLyrics(),
      camera: camera,
    ),
  ),
);

/// Closes the camera a new game opens by itself. On a phone that is the
/// scanner page over the idle screen, and these tests are about the screen
/// under it.
Future<void> closeAutoScanner(WidgetTester tester) async {
  final scanner = find.byType(ScannerScreen);
  if (scanner.evaluate().isEmpty) return;
  Navigator.of(tester.element(scanner)).pop();
  await tester.pumpAndSettle();
}

Future<void> reveal(GameController game) async {
  game.scan(card);
  await game.startPlayback();
  game.reveal();
}

void main() {
  // The per-device settings - the lyrics scale, whether the scores show -
  // live in the preferences, and a mocked value outlives the test that set it.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A phone, not the 800x600 the test binding defaults to.
  void usePhoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('the reveal fits a phone screen', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame();
    await reveal(game);

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();

    expect(find.text('2005'), findsOneWidget);
    expect(find.text('My Number One'), findsOneWidget);
    expect(find.text('Who got it right?'), findsOneWidget);
    // The target is stated once, next to the heading - not on every tile.
    expect(find.text('/ 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone turned over keeps one column, and widens it', (
    tester,
  ) async {
    // What the wide layout is not for: its column would be 214 pixels. The
    // one column takes the width instead of sitting in a 560 strip.
    tester.view.physicalSize = const Size(893, 412);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final game = buildGame();
    await reveal(game);

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();

    // The phone's own reveal card, not the stage and its column.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(revealInColumnKey), findsNothing);
    expect(find.text('2005'), findsOneWidget);

    final card = tester.getRect(find.text('My Number One'));
    expect(card.center.dx, closeTo(893 / 2, 1));
    expect(tester.getRect(find.byType(CenteredBody)).width, greaterThan(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('with the in-app player the round stays in the app', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final game = buildGame(launcher: const InTabLauncher());
    game.scan(card);
    await game.startPlayback();

    await tester.pumpWidget(
      wrap(game, spotify: FakeSession(SpotifyConnection.ready)),
    );
    await tester.pumpAndSettle();

    expect(find.text('The song is playing'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    // Nobody left the app, so there is nothing to come back from.
    expect(find.textContaining('Coming back'), findsNothing);

    // The scoreboard is already up, the song card is not - and nothing on the
    // screen may give the year away before the button is pressed.
    expect(find.text('Reveal the year'), findsOneWidget);
    expect(find.text('Scores'), findsOneWidget);
    expect(find.text('Player 1'), findsOneWidget);
    expect(find.text('2005'), findsNothing);
    expect(find.text('My Number One'), findsNothing);
  });

  testWidgets('the reveal button swaps in the song card', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame();
    game.scan(card);
    await game.startPlayback();

    await tester.pumpWidget(
      wrap(game, spotify: FakeSession(SpotifyConnection.ready)),
    );
    await tester.pumpAndSettle();

    // The whole panel reveals, not just the pill - it is tapped by whoever is
    // holding the phone, so the icon at the top has to work too.
    await tester.tap(find.byIcon(Icons.music_note));
    await tester.pumpAndSettle();

    expect(find.text('2005'), findsOneWidget);
    expect(find.text('My Number One'), findsOneWidget);
    expect(find.text('Reveal the year'), findsNothing);
    // Scoring only opens up once the year is out.
    await tester.tap(find.text('Player 1'));
    await tester.pump();
    expect(game.players.first.score, 1);

    // The tile flash owns a timer; it has to run out inside the test.
    await tester.pumpAndSettle();
  });

  testWidgets('without it the round still points at Spotify', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame();
    game.scan(card);
    await game.startPlayback();

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();

    expect(find.text('The song is playing in Spotify'), findsOneWidget);
    expect(find.textContaining('Coming back'), findsOneWidget);
    expect(find.text('Reveal the year'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
  });

  testWidgets('a refused track keeps the way back to Spotify', (tester) async {
    usePhoneScreen(tester);
    // The session is ready and says so all round - it just did not play this
    // track, so the link is what ran and the round has to say so.
    final game = buildGame();
    game.scan(card);
    await game.startPlayback();

    await tester.pumpWidget(
      wrap(game, spotify: FakeSession(SpotifyConnection.ready)),
    );
    await tester.pumpAndSettle();

    // The "Open in Spotify" button itself sits behind kIsWeb and cannot
    // render here, but it hangs off the same branch as everything below.
    expect(find.text('The song is playing in Spotify'), findsOneWidget);
    expect(find.textContaining('Coming back'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
    // Still nothing given away before the button.
    expect(find.text('2005'), findsNothing);
  });

  testWidgets('a YouTube Music round names YouTube Music', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame(service: MusicService.youtubeMusic);
    game.scan(card);
    await game.startPlayback();

    // A connected Spotify session changes nothing: the song went out by link.
    await tester.pumpWidget(
      wrap(game, spotify: FakeSession(SpotifyConnection.ready)),
    );
    await tester.pumpAndSettle();

    expect(find.text('The song is playing in YouTube Music'), findsOneWidget);
    expect(find.textContaining('Coming back'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
  });

  test('the countdown only drops out for the Spotify player in the tab', () {
    expect(needsCountdown(MusicService.spotify, sessionReady: true), isFalse);
    expect(needsCountdown(MusicService.spotify, sessionReady: false), isTrue);
    // YouTube Music always leaves by link, whatever Spotify is doing.
    expect(
      needsCountdown(MusicService.youtubeMusic, sessionReady: true),
      isTrue,
    );
    expect(
      needsCountdown(MusicService.youtubeMusic, sessionReady: false),
      isTrue,
    );
  });

  testWidgets('eight players are scaled down, not scrolled', (tester) async {
    usePhoneScreen(tester);
    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    final small = buildGame(players: 2);
    await reveal(small);
    await tester.pumpWidget(wrap(small));
    await tester.pumpAndSettle();
    final atFullSize = tester.getRect(find.text('Next round')).width;

    final full = buildGame(players: 8);
    await reveal(full);
    await tester.pumpWidget(wrap(full));
    await tester.pumpAndSettle();

    // Nothing scrolls, and every tile is reachable without looking for it.
    expect(find.byType(SingleChildScrollView), findsNothing);
    for (var index = 1; index <= 8; index++) {
      expect(find.text('Player $index'), findsOneWidget);
    }

    // The last thing on the screen is still on the screen, because the whole
    // body shrank to make room.
    expect(
      tester.getBottomLeft(find.text('Next round')).dy,
      lessThanOrEqualTo(screen),
    );
    expect(tester.getRect(find.text('Next round')).width, lessThan(atFullSize));
    expect(tester.takeException(), isNull);
  });

  /// Stands in for the camera: a button that scans [card].
  Widget fakeCamera(BuildContext context, ValueChanged<String> onCode) =>
      TextButton(
        onPressed: () => onCode(card),
        child: const Text('Scan the card'),
      );

  testWidgets('backing out of the camera after a reveal keeps the reveal', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final game = buildGame();
    await reveal(game);

    await tester.pumpWidget(wrap(game, camera: fakeCamera));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next round'));
    await tester.pumpAndSettle();
    expect(find.text('Scan the card'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(game.phase, RoundPhase.revealed);
    expect(find.text('My Number One'), findsOneWidget);
    expect(find.text('Next round'), findsOneWidget);
  });

  testWidgets('a scan from the reveal starts the next round', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame();
    await reveal(game);

    await tester.pumpWidget(wrap(game, camera: fakeCamera));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next round'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan the card'));
    await tester.pump();

    // The countdown is up over the screen now, the reveal is gone.
    expect(game.phase, RoundPhase.countdown);
    expect(game.isRevealed, isFalse);
  });

  testWidgets('a tap on a tile scores a point and flashes', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame();
    await reveal(game);

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Player 1'));
    await tester.pump();

    expect(game.players.first.score, 1);

    // The flash has to end on its own, otherwise the tile stays lit.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the idle screen shows the same tiles, without scoring', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final game = buildGame();

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();

    // A new game puts the camera up by itself; this is the screen under it.
    expect(find.byType(ScannerScreen), findsOneWidget);
    await closeAutoScanner(tester);
    expect(find.text('Scan a card'), findsOneWidget);
    expect(find.text('Scores'), findsOneWidget);

    await tester.tap(find.text('Player 1'));
    await tester.pumpAndSettle();

    expect(game.players.first.score, 0, reason: 'points only after the reveal');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a contest entry shows deck, country and rank', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame();
    await reveal(game);

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();

    expect(find.text('ESC  ·  Greece  ·  1st place'), findsOneWidget);
  });

  testWidgets('a plain song in a single deck gets no extra line', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final game = buildGame(
      categories: [
        SongCategory(
          id: 'german_songs',
          name: 'German Songs',
          description: '',
          songs: const [
            Song(title: 'A', artist: 'X', year: 2005, spotifyTrackId: 'a'),
          ],
        ),
      ],
    );
    await reveal(game);

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();

    // Only the app bar names the deck; the reveal card adds no origin line.
    expect(find.text('German Songs'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('the song nobody knows is swapped for another one', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final game = buildGame(
      launcher: const InTabLauncher(),
      categories: [twoSongs],
    );
    game.scan(card);
    await game.startPlayback();
    final unknown = game.currentSong!.title;

    await tester.pumpWidget(
      wrap(game, spotify: FakeSession(SpotifyConnection.ready)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nobody knows it — draw another'));
    await tester.pumpAndSettle();

    // In the tab there is no countdown, the new song is simply there.
    expect(game.phase, RoundPhase.playing);
    expect(game.currentSong!.title, isNot(unknown));
    expect(find.text('2005'), findsNothing, reason: 'still a secret');
  });

  group('without cards', () {
    testWidgets('a tap draws the year, and no camera opens', (tester) async {
      usePhoneScreen(tester);
      final game = buildGame(
        categories: [fourYears],
        launcher: const InTabLauncher(),
        fromYear: 2001,
        toYear: 2004,
      );

      await tester.pumpWidget(
        wrap(
          game,
          camera: fakeCamera,
          // A ready session, so the song starts in the tab and no countdown
          // comes between the tap and the round.
          spotify: FakeSession(SpotifyConnection.ready),
        ),
      );
      await tester.pumpAndSettle();

      // Nothing has been drawn yet: the room taps when it is ready, and
      // there is no scanner page over the screen.
      expect(find.byType(ScannerScreen), findsNothing);
      expect(find.text('Draw a year'), findsOneWidget);
      expect(find.text('2001 to 2004, 0 of 4 played'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.casino_outlined));
      await tester.pumpAndSettle();

      // A round like any other - the year is a secret until the reveal.
      expect(game.phase, RoundPhase.playing);
      expect(game.playedYears.length, 1);
      final first = game.currentYear!;
      expect(first, inInclusiveRange(2001, 2004));
      expect(find.text('$first'), findsNothing);

      game.reveal();
      await tester.pumpAndSettle();
      expect(find.text('$first'), findsOneWidget);

      // And the next round is the next tap, with another year.
      await tester.tap(find.text('Next round'));
      await tester.pumpAndSettle();

      expect(game.phase, RoundPhase.playing);
      expect(game.currentYear, isNot(first));
      expect(game.playedYears, {first, game.currentYear});
      expect(tester.takeException(), isNull);
    });

    testWidgets('the column draws it too, in the camera\'s place', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final game = buildGame(
        categories: [fourYears],
        launcher: const InTabLauncher(),
        fromYear: 2001,
        toYear: 2004,
      );

      await tester.pumpWidget(
        wrap(
          game,
          camera: fakeCamera,
          spotify: FakeSession(SpotifyConnection.ready),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Scan the card'), findsNothing);
      await tester.tap(find.text('Draw a year'));
      await tester.pumpAndSettle();
      expect(game.phase, RoundPhase.playing);

      await tester.tap(find.byKey(revealInColumnKey));
      await tester.pumpAndSettle();

      // Where the camera would be: the box that draws the next year.
      expect(find.text('Next year'), findsOneWidget);
      expect(find.text('Scan the card'), findsNothing);

      await tester.tap(find.text('Next year'));
      await tester.pumpAndSettle();
      expect(game.phase, RoundPhase.playing);
      expect(game.playedYears.length, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a range that is through starts over and says so', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final game = buildGame(
        categories: [fourYears],
        launcher: const InTabLauncher(),
        fromYear: 2001,
        toYear: 2004,
      );

      await tester.pumpWidget(
        wrap(game, spotify: FakeSession(SpotifyConnection.ready)),
      );
      await tester.pumpAndSettle();

      for (var round = 0; round < 4; round++) {
        // The circle on the idle screen, then the button under the reveal.
        await tester.tap(
          round == 0
              ? find.byIcon(Icons.casino_outlined)
              : find.text('Next round'),
        );
        await tester.pumpAndSettle();
        game.reveal();
        await tester.pumpAndSettle();
      }
      expect(game.playedYears.length, 4);
      expect(find.textContaining('starting over'), findsNothing);

      await tester.tap(find.text('Next round'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Every year from 2001 to 2004 has been played - '
          'starting over.',
        ),
        findsOneWidget,
      );
      expect(game.playedYears.length, 1);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the swap is a button a finger finds', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame(
      launcher: const InTabLauncher(),
      categories: [twoSongs],
    );
    game.scan(card);
    await game.startPlayback();

    await tester.pumpWidget(
      wrap(game, spotify: FakeSession(SpotifyConnection.ready)),
    );
    await tester.pumpAndSettle();

    // It is pressed in the middle of a round, often in the dark: a line of
    // text with a ripple was both hard to hit and the one thing on the panel
    // that looked left there.
    final swap = tester.getSize(
      find.ancestor(
        of: find.text('Nobody knows it — draw another'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(swap.height, greaterThanOrEqualTo(48));
    expect(swap.width, greaterThan(200));
  });

  testWidgets('the sync arrows reach the phone too', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame(launcher: const InTabLauncher());
    game.scan(card);
    await game.startPlayback();

    await tester.pumpWidget(wrap(game, spotify: SeekableSession()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync the words'));
    await tester.pumpAndSettle();

    // There is no column here, so the arrows go into the round's own stack of
    // blocks - the song plays on either way, which is the point of them.
    await tester.tap(find.byTooltip('The words earlier'));
    await tester.pumpAndSettle();

    expect(find.text('+100 ms'), findsOneWidget);
    expect(await LyricsSyncStore.load(), 100);
    expect(game.phase, RoundPhase.playing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a swap can be taken back', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame(
      launcher: const InTabLauncher(),
      categories: [twoSongs],
    );
    game.scan(card);
    await game.startPlayback();
    final unknown = game.currentSong!.title;

    await tester.pumpWidget(
      wrap(game, spotify: FakeSession(SpotifyConnection.ready)),
    );
    await tester.pumpAndSettle();
    expect(undoShown(tester), isFalse);

    await tester.tap(find.text('Nobody knows it — draw another'));
    await tester.pumpAndSettle();
    expect(game.currentSong!.title, isNot(unknown));

    expect(undoShown(tester), isTrue);
    await tester.tap(find.byTooltip('Back to the last song'));
    await tester.pumpAndSettle();

    expect(game.phase, RoundPhase.playing);
    expect(game.currentSong!.title, unknown);
    expect(undoShown(tester), isFalse);
  });

  testWidgets('a swap in the tab does not move the screen', (tester) async {
    usePhoneScreen(tester);
    final launches = <Completer<LaunchResult>>[];
    final game = buildGame(
      launcher: _QueuedLauncher(launches),
      categories: [twoSongs],
    );
    game.scan(card);
    final first = game.startPlayback();
    launches.single.complete(const LaunchResult.inTab());
    await first;

    await tester.pumpWidget(
      wrap(game, spotify: FakeSession(SpotifyConnection.ready)),
    );
    await tester.pumpAndSettle();
    final scores = tester.getTopLeft(find.text('Scores'));

    await tester.tap(find.text('Nobody knows it — draw another'));
    await tester.pump();
    // The launch of the new song is still out: the bar is gone for now, its
    // room is not.
    expect(game.playingInApp, isFalse);
    expect(tester.getTopLeft(find.text('Scores')), scores);

    launches.last.complete(const LaunchResult.inTab());
    await tester.pumpAndSettle();
    expect(game.playingInApp, isTrue);
    expect(tester.getTopLeft(find.text('Scores')), scores);
  });

  testWidgets('a year with one song offers no swap', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame();
    game.scan(card);
    await game.startPlayback();

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();

    expect(find.text('Nobody knows it — draw another'), findsNothing);
  });

  testWidgets('the in-app round has a bar to move around in the song', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final session = SeekableSession();
    final game = buildGame(launcher: const InTabLauncher());
    game.scan(card);
    await game.startPlayback();

    await tester.pumpWidget(wrap(game, spotify: session));
    await tester.pump();

    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('3:20'), findsOneWidget);

    await tester.tap(find.byTooltip('To the middle'));
    await tester.pump();
    expect(session.seeks.last, const Duration(seconds: 100));

    await tester.tap(find.byTooltip('From the start'));
    await tester.pump();
    expect(session.seeks.last, Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a link round has no seek bar - the song is out of reach', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final game = buildGame();
    game.scan(card);
    await game.startPlayback();

    await tester.pumpWidget(wrap(game, spotify: SeekableSession()));
    await tester.pump();

    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('a song the tab could not play turns into a link round', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final session = SeekableSession();
    final game = buildGame(launcher: const InTabLauncher());
    game.scan(card);
    await game.startPlayback();
    await tester.pumpWidget(wrap(game, spotify: session));
    await tester.pump();

    session.failPlayback('Playback failed');
    await tester.pump();

    expect(game.playingInApp, isFalse);
    expect(find.byType(Slider), findsNothing);
    expect(find.textContaining('could not play'), findsOneWidget);
  });

  testWidgets('the point that ended the game can be taken back', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final game = GameController(
      players: [
        GamePlayer(name: 'Player 1'),
        GamePlayer(name: 'Player 2'),
      ],
      categories: [escCategory],
      years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
      launcher: const SilentLauncher(),
      targetScore: 1,
    );
    await reveal(game);
    game.addPoint(game.players.first);
    game.nextRound();

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();
    expect(find.text('Player 1 wins'), findsOneWidget);

    await tester.tap(find.text('Back to the last round'));
    await tester.pumpAndSettle();

    expect(game.phase, RoundPhase.revealed);
    expect(find.text('Who got it right?'), findsOneWidget);
  });

  testWidgets('leaving a running game asks first', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame();

    await tester.pumpWidget(
      AppScope(
        years: game.years,
        categories: game.categories,
        spotify: NoSpotifySession(),
        link: TvLink(url: ''),
        service: ValueNotifier(game.service),
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GameScreen(controller: game),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await closeAutoScanner(tester);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Leave the game?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Scan a card'), findsOneWidget, reason: 'still in it');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('eight players get a third column and stay readable', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final game = buildGame(players: 8);
    await reveal(game);

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();

    final first = tester.getTopLeft(find.text('Player 1'));
    final third = tester.getTopLeft(find.text('Player 3'));
    expect(third.dy, closeTo(first.dy, 1), reason: 'three tiles in a row');
    // Rendered size, scale included: a name has to be read across a table.
    expect(tester.getSize(find.text('Player 1')).height, greaterThan(12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('with several decks the app bar counts them', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame(
      categories: [
        escCategory,
        SongCategory(
          id: 'german_songs',
          name: 'German Songs',
          description: '',
          songs: const [
            Song(title: 'A', artist: 'X', year: 1999, spotifyTrackId: 'a'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();

    await closeAutoScanner(tester);
    expect(find.text('2 categories'), findsOneWidget);
  });

  testWidgets('the lyrics open while guessing, without the name', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final game = buildGame();
    game.scan(card);
    await game.startPlayback();

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lyrics'));
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    // The words are the hint, the name would be the answer.
    expect(find.textContaining('My Number One'), findsNothing);
    expect(find.textContaining('Helena Paparizou'), findsNothing);
  });

  testWidgets('after the reveal the lyrics carry the name', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame();
    await reveal(game);

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lyrics'));
    await tester.pumpAndSettle();

    expect(find.text('My Number One · Helena Paparizou'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('a line lights up just before it is sung', (tester) async {
    usePhoneScreen(tester);
    final session = SeekableSession();
    // A tenth of a second before the line at 0:40 - close enough that the
    // lead is what decides, and the only thing that can.
    session.at = const Duration(milliseconds: 39900);
    final game = buildGame(launcher: const InTabLauncher());
    game.scan(card);
    await game.startPlayback();

    await tester.pumpWidget(wrap(game, spotify: session));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lyrics'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final style = DefaultTextStyle.of(
      tester.element(find.text('Second')),
    ).style;
    expect(style.fontWeight, FontWeight.w700);
  });

  testWidgets('in the tab the lyrics follow the song and seek on a tap', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final session = SeekableSession();
    final game = buildGame(launcher: const InTabLauncher());
    game.scan(card);
    await game.startPlayback();

    await tester.pumpWidget(wrap(game, spotify: session));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lyrics'));
    await tester.pumpAndSettle();
    // The sheet catches up with the player on its own tick.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final second = tester.widget<Text>(find.text('Second'));
    final third = tester.widget<Text>(find.text('Third'));
    final style = DefaultTextStyle.of(
      tester.element(find.text('Second')),
    ).style;
    final thirdStyle = DefaultTextStyle.of(
      tester.element(find.text('Third')),
    ).style;
    expect(second.data, 'Second');
    expect(third.data, 'Third');
    expect(style.fontWeight, FontWeight.w700);
    expect(thirdStyle.fontWeight, isNot(FontWeight.w700));

    await tester.tap(find.text('Third'));
    expect(session.seeks, [const Duration(minutes: 1)]);

    // The ticker stops with the sheet.
    Navigator.of(tester.element(find.text('Third'))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('a song without lyrics says so', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame();
    await reveal(game);

    await tester.pumpWidget(wrap(game, lyrics: _NoLyrics()));
    await tester.pumpAndSettle();

    // Where the button to the words would be: there is nothing to open, and
    // a dead button says less than the line that says why.
    expect(find.text('No lyrics for this song'), findsOneWidget);
    expect(find.text('Lyrics'), findsNothing);
  });

  testWidgets('lyrics that could not be loaded are asked for again on a tap', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final game = buildGame();
    await reveal(game);
    final lyrics = _FlakyLyrics();

    await tester.pumpWidget(wrap(game, lyrics: lyrics));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lyrics'));
    await tester.pumpAndSettle();

    // Not the same as a song without words.
    expect(find.text('No lyrics found for this song.'), findsNothing);
    expect(find.text('The lyrics could not be loaded.'), findsOneWidget);

    lyrics.down = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Back again'), findsOneWidget);
  });

  group('on a wide screen', () {
    /// A laptop on a projector, the browser in fullscreen.
    void useWideScreen(
      WidgetTester tester, {
      Size size = const Size(1920, 1080),
    }) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    test('landscape, and the size of a device it was meant for', () {
      expect(isWideScreen(const Size(1920, 1080)), isTrue);
      expect(isWideScreen(const Size(1280, 720)), isTrue);
      // Tablets on their side.
      expect(isWideScreen(const Size(1180, 820)), isTrue);
      expect(isWideScreen(const Size(1024, 768)), isTrue);
      // A phone turned over is landscape and nothing like the device: its
      // column would be 214 pixels. It keeps the one column, widened.
      expect(isWideScreen(const Size(956, 440)), isFalse);
      expect(isWideScreen(const Size(893, 412)), isFalse);
      expect(isWideScreen(const Size(667, 375)), isFalse);
      expect(isShortLandscape(const Size(893, 412)), isTrue);
      // Upright, where the one column belongs: a phone, a tablet, and a
      // browser window too narrow to put two things side by side.
      expect(isWideScreen(const Size(390, 844)), isFalse);
      expect(isShortLandscape(const Size(390, 844)), isFalse);
      expect(isWideScreen(const Size(820, 1180)), isFalse);
      expect(isWideScreen(const Size(1000, 1100)), isFalse);
    });

    // The floor of the layout and a 10 inch tablet on its side: the two
    // smallest screens that get it at all, where the blocks of the stage are
    // closest to adding up to more than the screen.
    for (final size in [const Size(900, 500), const Size(1024, 768)]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('the smallest screens play whole at $label', (tester) async {
        useWideScreen(tester, size: size);
        final game = buildGame();
        game.scan(card);
        await game.startPlayback();

        await tester.pumpWidget(wrap(game));
        await tester.pumpAndSettle();

        // The stage for the room, the column for whoever runs the game.
        // The reveal is only in the column: a banner telling the room about
        // a button it cannot reach was taking the words' room.
        expect(find.text('Reveal the year'), findsOneWidget);
        expect(find.text('Player 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the smallest screens reveal whole at $label', (
        tester,
      ) async {
        useWideScreen(tester, size: size);
        final game = buildGame();
        await reveal(game);

        await tester.pumpWidget(wrap(game));
        await tester.pumpAndSettle();

        // In the column, where the whole answer lives.
        expect(find.text('2005'), findsOneWidget);
        expect(find.text('My Number One'), findsOneWidget);
        expect(find.text('Who got it right?'), findsOneWidget);
        expect(find.text('Player 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the words are up while the room guesses', (tester) async {
      useWideScreen(tester);
      final game = buildGame();
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game));
      await tester.pumpAndSettle();

      // No button to press first: the stage is where the words live.
      expect(find.text('Second'), findsOneWidget);
      expect(find.text('Lyrics'), findsNothing);
      // In the column, and nowhere on the stage.
      expect(find.text('Reveal the year'), findsOneWidget);
      expect(find.textContaining('The song is playing'), findsNothing);
      expect(find.text('Player 1'), findsOneWidget);
      // The words are the hint, the name and the year are the answer.
      expect(find.textContaining('My Number One'), findsNothing);
      expect(find.textContaining('Helena Paparizou'), findsNothing);
      expect(find.text('2005'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the reveal is the camera\'s own slot', (tester) async {
      useWideScreen(tester, size: const Size(1024, 768));
      final game = buildGame();
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game, camera: fakeCamera));
      await tester.pumpAndSettle();

      // While the song runs there is no camera box at all - nothing to look
      // at, and the words are better off with the room.
      expect(find.text('Scan the card'), findsNothing);
      expect(find.text('Next round'), findsNothing);

      final slot = tester.getRect(find.byKey(revealInColumnKey));
      await tester.tap(find.byKey(revealInColumnKey));
      await tester.pumpAndSettle();

      expect(game.isRevealed, isTrue);
      // The year went to the stage. Only in the column: the stage keeps the
      // words.
      expect(find.text('2005'), findsOneWidget);

      // The scores share the camera's slot and come first - giving the
      // point is what opens it now.
      await tester.tap(find.text('Player 1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Scan the card'), findsOneWidget);
      // The camera has its own place at the foot of the column, under the
      // slot that just became the year. Neither displaces the other.
      final preview = tester.getRect(find.text('Scan the card'));
      expect(preview.top, greaterThan(slot.bottom));
      expect(preview.center.dx, lessThan(1024 * 0.33));
      expect(find.text('Next round'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the keys sit on the floor of the column', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      useWideScreen(tester, size: const Size(1280, 720));
      final game = buildGame(launcher: const InTabLauncher());
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(
        wrap(game, spotify: SeekableSession(), camera: fakeCamera),
      );
      await tester.pumpAndSettle();

      // The lowest key row, whichever it is.
      double lowestKey() {
        var low = 0.0;
        for (final shortcut in GameShortcut.values) {
          final found = find.text(shortcut.label);
          if (found.evaluate().isEmpty) continue;
          final bottom = tester.getRect(found).bottom;
          if (bottom > low) low = bottom;
        }
        return low;
      }

      // At the foot of the column: the band below them is the whole screen's,
      // not the column's. As a Flexible beside the controls they used to stop
      // in the middle of it.
      final column = tester.getRect(find.byKey(splitHandleKey));
      expect(lowestKey(), greaterThan(column.center.dy));
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the camera covers the keys instead of moving them', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      useWideScreen(tester, size: const Size(1280, 720));
      final game = buildGame(launcher: const InTabLauncher());
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(
        wrap(game, spotify: SeekableSession(), camera: fakeCamera),
      );
      await tester.pumpAndSettle();

      final keys = tester.getRect(find.text('Space'));
      expect(find.text('Scan the card'), findsNothing);

      game.reveal();
      await tester.pumpAndSettle();

      // The scores share the camera's slot and come first - give the point
      // before the preview that covers the keys can come up at all. A scan
      // is now waiting on the fake camera forever, so a bounded pump flushes
      // the tile's own flash instead of the unsettled `pumpAndSettle`.
      await tester.tap(find.text('Player 1'));
      await tester.pump(const Duration(milliseconds: 300));

      // The preview is an overlay at the foot of the column, so the keys stay
      // down where they were and are covered. They used to be pushed up by
      // it, which moved the one block on the screen that is read by sitting
      // still. (The row itself is one chip shorter after a reveal - the key
      // that revealed is dead - so it settles a little lower, never higher.)
      expect(
        tester.getRect(find.text('Space')).top,
        greaterThanOrEqualTo(keys.top),
      );
      final preview = tester.getRect(find.text('Scan the card'));
      expect(preview.bottom, greaterThan(keys.top));
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the reveal card is dragged taller', (tester) async {
      useWideScreen(tester, size: const Size(1280, 720));
      final game = buildGame();
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game));
      await tester.pumpAndSettle();

      final before = tester.getSize(find.byKey(revealInColumnKey)).height;
      await tester.drag(find.byKey(slotHandleKey), const Offset(0, 120));
      await tester.pumpAndSettle();

      final after = tester.getSize(find.byKey(revealInColumnKey)).height;
      expect(after, greaterThan(before + 80));
      // And it is kept, the way the width between the halves is.
      expect(await SlotHeightStore.load(), greaterThan(SlotHeightStore.normal));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the card it is still looking at does not count', (
      tester,
    ) async {
      useWideScreen(tester, size: const Size(1024, 768));
      final game = buildGame(
        years: const {'182ca01194a98f0b': 2005, '91bd5e0e2c7a4f31': 2005},
      );
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(
        wrap(
          game,
          camera: (context, onCode) => Column(
            children: [
              TextButton(
                onPressed: () => onCode(card),
                child: const Text('Scan the card'),
              ),
              TextButton(
                onPressed: () => onCode(otherCard),
                child: const Text('Scan another'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(revealInColumnKey));
      await tester.pumpAndSettle();

      // The scores share the slot the camera opens in and come first.
      await tester.tap(find.text('Player 1'));
      await tester.pumpAndSettle();

      // The card that was just played is lying in front of the camera. It
      // would otherwise start its own round again, right over the reveal.
      await tester.tap(find.text('Scan the card'));
      await tester.pumpAndSettle();

      expect(game.phase, RoundPhase.revealed);
      // Only in the column: the stage keeps the words.
      expect(find.text('2005'), findsOneWidget);
      expect(find.text('Scan another'), findsOneWidget);

      // A card somebody held up does.
      await tester.tap(find.text('Scan another'));
      await tester.pumpAndSettle();

      expect(game.phase, isNot(RoundPhase.revealed));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a game won while the camera waits ends', (tester) async {
      useWideScreen(tester, size: const Size(1024, 768));
      final game = GameController(
        players: [GamePlayer(name: 'Player 1')],
        categories: [escCategory],
        years: YearDatabase.inMemory(
          defaults: const {'182ca01194a98f0b': 2005, '91bd5e0e2c7a4f31': 2005},
        ),
        launcher: const SilentLauncher(),
        targetScore: 1,
      );
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(
        wrap(
          game,
          camera: (context, onCode) => TextButton(
            onPressed: () => onCode(otherCard),
            child: const Text('Scan another'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(revealInColumnKey));
      await tester.pumpAndSettle();

      // The winning point is given from the scores sharing the camera's
      // slot - the scan it would otherwise have started never happens, the
      // game being over by then. A bounded pump rather than `pumpAndSettle`:
      // the tile's own flash is a real timer and nothing is left pending on
      // a scan to unsettle it.
      await tester.tap(find.text('Player 1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Scan another'), findsNothing);
      expect(game.phase, RoundPhase.finished);
      expect(find.text('Player 1 wins'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the keys move the song and reveal the year', (tester) async {
      useWideScreen(tester);
      final session = SeekableSession();
      final game = buildGame(launcher: const InTabLauncher());
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game, spotify: session));
      await tester.pumpAndSettle();

      // The session sits at 0:42 of a 3:20 song.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(session.pauses, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(session.seeks.last, const Duration(seconds: 52));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      expect(session.seeks.last, const Duration(seconds: 32));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      expect(session.seeks.last, const Duration(seconds: 100));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(session.seeks.last, Duration.zero);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(game.isRevealed, isTrue);

      // Nothing left to reveal, and the keys do not reveal it twice.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(game.phase, RoundPhase.revealed);
    });

    testWidgets('N swaps the song and Z takes it back', (tester) async {
      useWideScreen(tester);
      // In the tab, where there is no countdown between the swap and the
      // next song - and where a laptop with these keys plays anyway.
      final game = buildGame(
        launcher: const InTabLauncher(),
        categories: [twoSongs],
      );
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(
        wrap(game, spotify: FakeSession(SpotifyConnection.ready)),
      );
      await tester.pumpAndSettle();

      final first = game.currentSong!.title;

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(game.currentSong!.title, isNot(first));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pumpAndSettle();
      expect(game.currentSong!.title, first);

      // Nothing to take back twice, and the key says so by doing nothing.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pumpAndSettle();
      expect(game.currentSong!.title, first);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a year with one song ignores the swap key', (tester) async {
      useWideScreen(tester);
      final game = buildGame(launcher: const InTabLauncher());
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(
        wrap(game, spotify: FakeSession(SpotifyConnection.ready)),
      );
      await tester.pumpAndSettle();

      // A key does only what a finger could, and there is no swap button here.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();

      expect(game.currentSong!.title, 'My Number One');
      expect(find.text('No other song for this year.'), findsNothing);
    });

    testWidgets('a link round only takes the reveal key', (tester) async {
      useWideScreen(tester);
      final session = SeekableSession();
      final game = buildGame();
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game, spotify: session));
      await tester.pumpAndSettle();

      // The song is out of reach of a finger, so it is out of reach of a key.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(session.pauses, 0);
      expect(session.seeks, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(game.isRevealed, isTrue);
    });

    testWidgets('the keys are only written down where there are keys', (
      tester,
    ) async {
      // The check for a leftover override runs before any tearDown, so this
      // one is put back inside the test.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      useWideScreen(tester);
      final game = buildGame(launcher: const InTabLauncher());
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game, spotify: SeekableSession()));
      await tester.pumpAndSettle();

      // In the column, not on the stage: the room cannot press them.
      expect(find.text('Space'), findsOneWidget);
      expect(find.text('Enter'), findsOneWidget);
      expect(find.text('↑ W'), findsOneWidget);
      // Only what works: this year holds one song, so there is no swap.
      expect(find.text('N'), findsNothing);
      expect(
        tester.getCenter(find.text('Space')).dx,
        lessThan(tester.getCenter(find.byType(LyricsView)).dx),
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(wrap(game, spotify: SeekableSession()));
      await tester.pumpAndSettle();

      expect(find.text('Space'), findsNothing);
      expect(find.text('Enter'), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the column reveals too, for whoever runs the game', (
      tester,
    ) async {
      useWideScreen(tester);
      final game = buildGame();
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game));
      await tester.pumpAndSettle();

      // Not the card on the stage - the button beside the camera.
      await tester.tap(find.byKey(revealInColumnKey));
      await tester.pumpAndSettle();

      expect(game.isRevealed, isTrue);
      // Only in the column: the stage keeps the words.
      expect(find.text('2005'), findsOneWidget);
      expect(find.text('Reveal the year'), findsNothing);
    });

    testWidgets('the divider drags the two halves and is remembered', (
      tester,
    ) async {
      useWideScreen(tester, size: const Size(1280, 720));
      final game = buildGame();
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game));
      await tester.pumpAndSettle();

      final column = tester.getRect(find.byKey(revealInColumnKey));
      final words = tester.getRect(find.byType(LyricsView));

      await tester.drag(find.byKey(splitHandleKey), const Offset(120, 0));
      await tester.pumpAndSettle();

      // The column got what the stage lost - 120 less the drag slop the
      // tester swallows before it starts reporting.
      expect(
        tester.getRect(find.byKey(revealInColumnKey)).width,
        greaterThan(column.width + 80),
      );
      expect(
        tester.getRect(find.byType(LyricsView)).width,
        lessThan(words.width - 80),
      );

      // It is a property of the room, so it outlives the screen.
      expect(await ColumnWidthStore.load(), greaterThan(0.28));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no app bar, and the menu in the screen\'s corner', (
      tester,
    ) async {
      useWideScreen(tester, size: const Size(1024, 768));
      final game = buildGame();
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game));
      await tester.pumpAndSettle();

      // 56 pixels of a landscape phone's 412 are the stage's instead.
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('ESC'), findsNothing);

      // Top right of the whole screen, which belongs to neither half.
      final menu = tester.getCenter(find.byTooltip('Menu'));
      expect(menu.dx, greaterThan(1024 * 0.9));
      expect(menu.dy, lessThan(60));

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Reset scores'), findsOneWidget);
      // The bar's back arrow went with it, so the way out is in here.
      expect(find.text('Leave the game'), findsOneWidget);
      // And the size of the words, which was a row in the column.
      expect(find.text('Bigger words'), findsOneWidget);
    });

    testWidgets('the player is a band across the bottom', (tester) async {
      useWideScreen(tester, size: const Size(1024, 768));
      final session = SeekableSession();
      final game = buildGame(launcher: const InTabLauncher());
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game, spotify: session));
      await tester.pumpAndSettle();

      final track = tester.getRect(find.byType(Slider));
      // Wider than the whole side column, where it used to be ~190 of 214.
      expect(track.width, greaterThan(400));
      // Along the bottom, under both halves.
      expect(track.center.dy, greaterThan(412 * 0.8));

      // The buttons came along, left of the track where the column is.
      // The fake session is paused, so the big one offers to play on.
      expect(find.byTooltip('Play on'), findsOneWidget);
      expect(
        tester.getCenter(find.byTooltip('Play on')).dx,
        lessThan(track.left),
      );

      await tester.tap(find.byTooltip('To the middle'));
      await tester.pump();
      expect(session.seeks.last, const Duration(seconds: 100));

      // The swap stayed in the column.
      expect(find.textContaining('Nobody knows it'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the band stays through a swap', (tester) async {
      useWideScreen(tester, size: const Size(1024, 768));
      final launches = <Completer<LaunchResult>>[];
      final game = buildGame(
        launcher: _QueuedLauncher(launches),
        categories: [twoSongs],
      );
      game.scan(card);
      final first = game.startPlayback();
      launches.single.complete(const LaunchResult.inTab());
      await first;

      await tester.pumpWidget(
        wrap(game, spotify: FakeSession(SpotifyConnection.ready)),
      );
      await tester.pumpAndSettle();
      final track = tester.getRect(find.byType(Slider));

      await tester.tap(find.text('Nobody knows it'));
      await tester.pump();

      // The launch of the new song is still out, so the round is not in the
      // tab - and the band is still exactly where it was. Hidden for those
      // frames, it blinked out and back on every swap (2026-10-27).
      expect(game.playingInApp, isFalse);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(tester.getRect(find.byType(Slider)), track);

      launches.last.complete(const LaunchResult.inTab());
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(Slider)), track);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a link round gets no band, and the stage the height', (
      tester,
    ) async {
      final words = <double>[];
      for (final launcher in [const InTabLauncher(), const SilentLauncher()]) {
        useWideScreen(tester, size: const Size(1024, 768));
        final game = buildGame(launcher: launcher);
        game.scan(card);
        await game.startPlayback();

        await tester.pumpWidget(wrap(game, spotify: SeekableSession()));
        await tester.pumpAndSettle();

        words.add(tester.getSize(find.byType(LyricsView)).height);
      }

      // A song handed over by link is out of reach, so there is no band and
      // nothing kept in reserve for one: the words get what the in-app round
      // spends on it.
      expect(find.byType(Slider), findsNothing);
      expect(find.byTooltip('Play on'), findsNothing);
      expect(words.last, greaterThan(words.first));
    });

    testWidgets('the sync mode sets the words against the running song', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'lyrics.sync': 200});
      useWideScreen(tester);
      final session = SeekableSession()..nowPlaying = true;
      final game = buildGame(launcher: const InTabLauncher());
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game, spotify: session));
      await tester.pumpAndSettle();

      // Nothing of it on the screen until it is asked for.
      expect(find.text('Sync the words'), findsNothing);

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync the words'));
      await tester.pumpAndSettle();

      // The arrows are in the column, on what the device had - and the song
      // plays on, which is the whole reason this is not a dialog any more.
      expect(find.text('Sync the words'), findsOneWidget);
      expect(find.text('+200 ms'), findsOneWidget);
      expect(session.pauses, 0);
      expect(session.isPlaying, isTrue);

      await tester.tap(find.byTooltip('The words earlier'));
      await tester.pumpAndSettle();
      expect(find.text('+300 ms'), findsOneWidget);
      expect(await LyricsSyncStore.load(), 300);
      expect(tester.widget<LyricsView>(find.byType(LyricsView)).syncMs, 300);

      await tester.tap(find.byTooltip('The words later'));
      await tester.pumpAndSettle();
      expect(find.text('+200 ms'), findsOneWidget);

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done syncing the words'));
      await tester.pumpAndSettle();

      expect(find.text('Sync the words'), findsNothing);
      expect(await LyricsSyncStore.load(), 200);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the keys move the words and say the number', (tester) async {
      useWideScreen(tester);
      final game = buildGame(launcher: const InTabLauncher());
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game, spotify: SeekableSession()));
      await tester.pumpAndSettle();

      // Control, because the bare letters move the song.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pump();

      // Said over the screen, where whoever pressed it is looking.
      expect(find.text('Words +100 ms'), findsOneWidget);
      expect(await LyricsSyncStore.load(), 100);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(find.text('Words -100 ms'), findsOneWidget);
      expect(tester.widget<LyricsView>(find.byType(LyricsView)).syncMs, -100);

      // And it goes again by itself.
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('Words '), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the menu takes the scores off the stage', (tester) async {
      useWideScreen(tester, size: const Size(1024, 768));
      final game = buildGame();
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game));
      await tester.pumpAndSettle();

      double lyricsHeight() => tester.getSize(find.byType(LyricsView)).height;
      final withScores = lyricsHeight();
      expect(find.text('Player 1'), findsOneWidget);

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide the scores'));
      await tester.pumpAndSettle();

      // The words take what the strip and its heading had.
      expect(find.text('Player 1'), findsNothing);
      expect(find.text('Scores'), findsNothing);
      expect(lyricsHeight(), greaterThan(withScores));

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show the scores'));
      await tester.pumpAndSettle();

      expect(find.text('Player 1'), findsOneWidget);
      expect(lyricsHeight(), withScores);
    });

    testWidgets('hidden, the reveal hands out no points', (tester) async {
      SharedPreferences.setMockInitialValues({'scores.shown': false});
      useWideScreen(tester);
      final game = buildGame();
      await reveal(game);

      await tester.pumpWidget(wrap(game));
      await tester.pumpAndSettle();

      // The year is the whole stage. Nothing to tap, so nothing is counted -
      // that is what the option is for.
      // Only in the column: the stage keeps the words.
      expect(find.text('2005'), findsOneWidget);
      expect(find.text('Who got it right?'), findsNothing);
      expect(find.text('Player 1'), findsNothing);
      expect(game.players.first.score, 0);
    });

    testWidgets('the words get the room on a short stage', (tester) async {
      final padding = <double>[];
      // The floor of the layout against a 1080p wall: the box of the one is a
      // fraction of the other's.
      for (final size in [const Size(900, 500), const Size(1920, 1080)]) {
        useWideScreen(tester, size: size);
        final game = buildGame();
        game.scan(card);
        await game.startPlayback();

        await tester.pumpWidget(wrap(game));
        await tester.pumpAndSettle();

        final view = tester.widget<LyricsView>(find.byType(LyricsView));
        padding.add(view.padding.top + view.padding.bottom);
        expect(tester.takeException(), isNull);
      }

      // A share of the box, capped at the projector's 28 and 72: the wall
      // sits on the cap, the small screen below it. Fixed, those 100 pixels
      // were most of a small box.
      expect(padding.last, 100);
      expect(padding.first, lessThan(padding.last));
      expect(padding.first, greaterThan(20));
    });

    testWidgets('the words on the stage are sized from the column', (
      tester,
    ) async {
      useWideScreen(tester);
      final game = buildGame();
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game));
      await tester.pumpAndSettle();

      // A line carries its size in the style around it, not on the Text.
      double lineSize() => tester
          .widget<AnimatedDefaultTextStyle>(
            find
                .ancestor(
                  of: find.text('Second'),
                  matching: find.byType(AnimatedDefaultTextStyle),
                )
                .first,
          )
          .style
          .fontSize!;
      final normal = lineSize();

      // Through the menu, which is where the size lives now - a press closes
      // it, so a second step is a second trip.
      Future<void> step(String entry) async {
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry));
        await tester.pumpAndSettle();
      }

      await step('Bigger words');
      expect(lineSize(), closeTo(normal * LyricsScaleStore.step, 0.01));

      await step('Smaller words');
      expect(lineSize(), closeTo(normal, 0.01));
      // Nothing of the number on the screen, and none in the menu either:
      // two fingers on the words are the way this is set, and a percentage
      // nobody can act on was taking a row of the menu.
      expect(find.textContaining('Words '), findsNothing);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('two fingers on the words set their size', (tester) async {
      useWideScreen(tester);
      final game = buildGame();
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game));
      await tester.pumpAndSettle();

      double lineSize() => tester
          .widget<AnimatedDefaultTextStyle>(
            find
                .ancestor(
                  of: find.text('Second'),
                  matching: find.byType(AnimatedDefaultTextStyle),
                )
                .first,
          )
          .style
          .fontSize!;
      final normal = lineSize();

      // Two fingers, pulled apart to twice their distance.
      final centre = tester.getCenter(find.byType(LyricsView));
      final one = await tester.startGesture(centre - const Offset(60, 0));
      final two = await tester.startGesture(centre + const Offset(60, 0));
      await one.moveBy(const Offset(-60, 0));
      await two.moveBy(const Offset(60, 0));
      await tester.pumpAndSettle();

      // Damped on purpose: twice the distance is about a third bigger, not
      // twice as big - the words are set once for a room, and a raw pinch
      // overshot every time (2026-10-27).
      expect(lineSize(), greaterThan(normal * 1.2));
      expect(lineSize(), lessThan(normal * 1.55));
      await one.up();
      await two.up();
      await tester.pumpAndSettle();

      // Kept, like every other size of the words.
      expect(await LyricsScaleStore.load(), greaterThan(1.2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the size stays set after the reveal', (tester) async {
      useWideScreen(tester);
      final game = buildGame();
      await reveal(game);

      await tester.pumpWidget(wrap(game));
      await tester.pumpAndSettle();

      // The words stay up through the reveal, so their size still matters.
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bigger words'));
      await tester.pumpAndSettle();

      expect(
        await LyricsScaleStore.load(),
        closeTo(LyricsScaleStore.step, 0.01),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the reveal leaves the words on the stage', (tester) async {
      useWideScreen(tester);
      final game = buildGame();
      await reveal(game);

      // Giving the point below opens the camera's slot now, so a stand-in
      // is needed - the real scanner would otherwise try to build itself.
      await tester.pumpWidget(wrap(game, camera: fakeCamera));
      await tester.pumpAndSettle();

      // Only in the column: the stage keeps the words.
      expect(find.text('2005'), findsOneWidget);
      expect(find.text('My Number One'), findsOneWidget);
      expect(find.text('Helena Paparizou'), findsOneWidget);
      expect(find.text('ESC  ·  Greece  ·  1st place'), findsOneWidget);
      expect(find.text('Who got it right?'), findsOneWidget);
      // The answer is in the column and nowhere near the words, which the
      // room is still reading.
      expect(find.byType(LyricsView), findsOneWidget);
      expect(find.text('First'), findsOneWidget);
      expect(
        tester.getCenter(find.text('2005')).dx,
        lessThan(tester.getRect(find.byType(LyricsView)).left),
      );

      await tester.tap(find.text('Player 1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(game.players.first.score, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the camera opens in the column, beside the reveal', (
      tester,
    ) async {
      useWideScreen(tester);
      final game = buildGame(
        years: const {'182ca01194a98f0b': 2005, '91bd5e0e2c7a4f31': 2005},
      );
      await reveal(game);

      // A fresh card, not `fakeCamera`'s own: giving the point below arms
      // the stale-card guard exactly as the auto-scan would, and `card` is
      // the one it is guarding against.
      await tester.pumpWidget(
        wrap(
          game,
          camera: (context, onCode) => TextButton(
            onPressed: () => onCode(otherCard),
            child: const Text('Scan the card'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The scores share the camera's slot and come first - giving the
      // point is what opens it, not a button of its own any more.
      await tester.tap(find.text('Player 1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Scan the card'), findsOneWidget);
      expect(find.byType(ScannerScreen), findsNothing, reason: 'no new page');
      // The room still has the year to look at while the next card comes up.
      // Only in the column: the stage keeps the words.
      expect(find.text('2005'), findsOneWidget);

      await tester.tap(find.text('Scan the card'));
      await tester.pump();

      expect(game.phase, RoundPhase.countdown);
      expect(find.text('Scan the card'), findsNothing);
    });

    testWidgets('closing the camera keeps the reveal', (tester) async {
      useWideScreen(tester);
      final game = buildGame();
      await reveal(game);

      await tester.pumpWidget(wrap(game, camera: fakeCamera));
      await tester.pumpAndSettle();

      // The scores share the camera's slot and come first - giving the
      // point is what opens it, not a button of its own any more.
      await tester.tap(find.text('Player 1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close the camera'));
      await tester.pumpAndSettle();

      expect(game.phase, RoundPhase.revealed);
      expect(find.text('Scan the card'), findsNothing);
      expect(find.text('Next round'), findsOneWidget);
      // Only in the column: the stage keeps the words.
      expect(find.text('2005'), findsOneWidget);

      // And it opens again, nothing left stuck from the first time.
      await tester.tap(find.text('Next round'));
      await tester.pumpAndSettle();
      expect(find.text('Scan the card'), findsOneWidget);
    });

    testWidgets('a new game opens the camera by itself', (tester) async {
      useWideScreen(tester);
      final game = buildGame();

      await tester.pumpWidget(wrap(game, camera: fakeCamera));
      await tester.pumpAndSettle();

      // No tap on a button whose only job is to open the camera: the first
      // card is what the game wants, so the box is already live.
      expect(find.text('Scores'), findsOneWidget);
      expect(find.text('Scan the card'), findsOneWidget);

      await tester.tap(find.text('Scan the card'));
      await tester.pump();

      expect(game.phase, RoundPhase.countdown);
    });

    testWidgets('a game resumed mid-round keeps the camera shut', (
      tester,
    ) async {
      useWideScreen(tester);
      final game = buildGame();
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(wrap(game, camera: fakeCamera));
      await tester.pumpAndSettle();

      // There is a song running: the camera belongs to the reveal, which is
      // what opens it from the second card on.
      expect(find.text('Scan the card'), findsNothing);
      expect(find.text('Reveal the year'), findsOneWidget);
    });

    testWidgets('the words follow the player once the launch says so', (
      tester,
    ) async {
      useWideScreen(tester);
      final session = SeekableSession();
      final lyrics = FakeLyrics();
      final launcher = LateInTabLauncher();
      final game = buildGame(launcher: launcher);
      game.scan(card);
      final playback = game.startPlayback();

      await tester.pumpWidget(wrap(game, spotify: session, lyrics: lyrics));
      await tester.pumpAndSettle();

      FontWeight? weightOf(String line) =>
          DefaultTextStyle.of(tester.element(find.text(line))).style.fontWeight;

      // Where the song plays is not known yet, so nothing is lit.
      expect(find.text('Second'), findsOneWidget);
      expect(weightOf('Second'), isNot(FontWeight.w700));

      launcher.answer.complete(const LaunchResult.inTab());
      await playback;
      await tester.pump();
      // The stage catches up with the player on its own tick.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(game.playingInApp, isTrue);
      expect(weightOf('Second'), FontWeight.w700);
      expect(weightOf('Third'), isNot(FontWeight.w700));
      // Picked again for the recording that plays, now that its length is in.
      expect(lyrics.asked.last, const Duration(seconds: 200));

      await tester.tap(find.text('Third'));
      expect(session.seeks, [const Duration(minutes: 1)]);
    });

    testWidgets('eight players fit a 720p projector', (tester) async {
      useWideScreen(tester, size: const Size(1280, 720));
      final game = buildGame(players: 8, launcher: const InTabLauncher());
      game.scan(card);
      await game.startPlayback();

      await tester.pumpWidget(
        wrap(game, spotify: SeekableSession(), camera: fakeCamera),
      );
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);
      expect(tester.takeException(), isNull);

      game.reveal();
      await tester.pumpAndSettle();

      for (var index = 1; index <= 8; index++) {
        expect(find.text('Player $index'), findsOneWidget);
        expect(
          tester.getBottomLeft(find.text('Player $index')).dy,
          lessThan(720),
        );
      }
      // Readable from the back of the room: rendered size, scale included.
      expect(tester.getRect(find.text('Player 1')).height, greaterThan(16));
      // The scores share the camera's slot and come first, so it is not a
      // button yet.
      expect(find.text('Scan the card'), findsNothing);

      await tester.tap(find.text('Player 1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Giving the point is what opens the camera now.
      expect(find.text('Scan the card'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the cast button', () {
    testWidgets('is in the corner, beside the menu', (tester) async {
      usePhoneScreen(tester);
      final session = _PickySession();
      final game = buildGame(launcher: const InTabLauncher());
      await reveal(game);

      await tester.pumpWidget(wrap(game, spotify: session));
      await tester.pump();

      // Where the song comes out of is a question for whoever runs the game,
      // and one worth reaching between rounds as well as during one - so it
      // sits with the menu rather than in the controls of a running song.
      expect(find.byTooltip('Where the song plays'), findsOne);
    });

    testWidgets('a session with nothing to pick draws none', (tester) async {
      usePhoneScreen(tester);
      final game = buildGame(launcher: const InTabLauncher());
      await reveal(game);

      await tester.pumpWidget(
        wrap(game, spotify: FakeSession(SpotifyConnection.ready)),
      );
      await tester.pump();

      expect(find.byTooltip('Where the song plays'), findsNothing);
    });

    testWidgets('the game being over lets the device go', (tester) async {
      usePhoneScreen(tester);
      final session = _PickySession();
      final game = buildGame(players: 1, launcher: const InTabLauncher());
      await reveal(game);

      await tester.pumpWidget(wrap(game, spotify: session));
      await tester.pump();

      // The points that win it: the game is over, and the speaker it played
      // on must not stay coupled to it.
      for (var i = 0; i < game.targetScore; i++) {
        game.addPoint(game.players.first);
      }
      game.nextRound();
      await tester.pump();

      expect(game.phase, RoundPhase.finished);
      expect(session.released, 1);
    });
  });
}

/// A session that can be asked where to play, like Spotify Connect.
class _PickySession extends FakeSession {
  _PickySession() : super(SpotifyConnection.ready);

  final List<String?> picked = <String?>[];
  int released = 0;

  @override
  bool get canPickDevice => true;

  @override
  List<PlaybackDevice> get devices => const [
    PlaybackDevice(
      id: 'phone',
      name: 'Jakobs Phone',
      type: 'Smartphone',
      isActive: false,
    ),
    PlaybackDevice(
      id: 'tv',
      name: 'Living room TV',
      type: 'TV',
      isActive: false,
    ),
  ];

  @override
  Future<void> pickDevice(String? id) async => picked.add(id);

  @override
  Future<void> releasePlayback() async => released++;
}

class _FlakyLyrics implements LyricsSource {
  bool down = true;

  @override
  Future<Lyrics?> find(Song song, {Duration? duration}) async {
    if (down) throw const LyricsUnavailable('HTTP 429');
    return Lyrics.plain('Back again');
  }
}

class _NoLyrics implements LyricsSource {
  @override
  Future<Lyrics?> find(Song song, {Duration? duration}) async => null;
}

/// Whether the undo of a swap can be pressed. The button itself is always
/// there - greyed out is what says there is nothing to take back.
bool undoShown(WidgetTester tester) =>
    tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Back to the last song'),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed !=
    null;

/// Answers each launch only when the test completes its entry in [launches].
class _QueuedLauncher implements SongLauncher {
  _QueuedLauncher(this.launches);

  final List<Completer<LaunchResult>> launches;

  @override
  Future<LaunchResult> open(Song song) {
    final launch = Completer<LaunchResult>();
    launches.add(launch);
    return launch.future;
  }
}
