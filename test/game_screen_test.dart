import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anno/data/year_database.dart';
import 'package:anno/game/game_controller.dart';
import 'package:anno/models/player.dart';
import 'package:anno/models/song.dart';
import 'package:anno/models/song_category.dart';
import 'package:anno/music/music_service.dart';
import 'package:anno/music/song_launcher.dart';
import 'package:anno/music/spotify_session.dart';
import 'package:anno/ui/app_scope.dart';
import 'package:anno/ui/game_screen.dart';
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

const card = 'https://play-the-music.com/de/year/182ca01194a98f0b';

GameController buildGame({
  int players = 2,
  List<SongCategory>? categories,
  SongLauncher launcher = const SilentLauncher(),
  MusicService service = MusicService.spotify,
}) => GameController(
  players: [
    for (var i = 0; i < players; i++) GamePlayer(name: 'Player ${i + 1}'),
  ],
  categories: categories ?? [escCategory],
  years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
  launcher: launcher,
  service: service,
);

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
  String? _playbackError;

  @override
  Duration get duration => const Duration(seconds: 200);

  @override
  Duration get position => const Duration(seconds: 42);

  @override
  String? get playbackError => _playbackError;

  void failPlayback(String message) {
    _playbackError = message;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async => seeks.add(position);
}

Widget wrap(GameController game, {SpotifySession? spotify}) => AppScope(
  years: game.years,
  categories: game.categories,
  spotify: spotify ?? NoSpotifySession(),
  service: ValueNotifier(game.service),
  child: MaterialApp(
    theme: buildTheme(),
    home: GameScreen(controller: game),
  ),
);

Future<void> reveal(GameController game) async {
  game.scan(card);
  await game.startPlayback();
  game.reveal();
}

void main() {
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

    await tester.tap(find.text('Nobody knows it? Draw another'));
    await tester.pumpAndSettle();

    // In the tab there is no countdown, the new song is simply there.
    expect(game.phase, RoundPhase.playing);
    expect(game.currentSong!.title, isNot(unknown));
    expect(find.text('2005'), findsNothing, reason: 'still a secret');
  });

  testWidgets('a year with one song offers no swap', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame();
    game.scan(card);
    await game.startPlayback();

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();

    expect(find.text('Nobody knows it? Draw another'), findsNothing);
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

    expect(find.text('2 categories'), findsOneWidget);
  });
}
