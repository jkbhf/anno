import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:play/data/year_database.dart';
import 'package:play/game/game_controller.dart';
import 'package:play/models/player.dart';
import 'package:play/models/song.dart';
import 'package:play/models/song_category.dart';
import 'package:play/music/spotify_launcher.dart';
import 'package:play/music/spotify_session.dart';
import 'package:play/ui/app_scope.dart';
import 'package:play/ui/game_screen.dart';
import 'package:play/ui/theme.dart';

class SilentLauncher implements SpotifyLauncher {
  const SilentLauncher();

  @override
  Future<SpotifyLaunchResult> open(Song song) async =>
      const SpotifyLaunchResult.ok();
}

const card = 'https://play-the-music.com/de/year/182ca01194a98f0b';

GameController buildGame({int players = 2, List<SongCategory>? categories}) =>
    GameController(
      players: [
        for (var i = 0; i < players; i++) GamePlayer(name: 'Player ${i + 1}'),
      ],
      categories: categories ?? [escCategory],
      years: YearDatabase.inMemory(defaults: {'182ca01194a98f0b': 2005}),
      launcher: const SilentLauncher(),
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

Widget wrap(GameController game, {SpotifySession? spotify}) => AppScope(
  years: game.years,
  categories: game.categories,
  spotify: spotify ?? NoSpotifySession(),
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
    final game = buildGame();
    game.scan(card);
    await game.startPlayback();

    await tester.pumpWidget(
      wrap(game, spotify: FakeSession(SpotifyConnection.ready)),
    );
    await tester.pumpAndSettle();

    expect(find.text('The song is playing'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
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
          id: 'rock_pop',
          name: 'Rock & Pop Classics',
          description: '',
          songs: const [Song(title: 'A', artist: 'X', year: 2005)],
        ),
      ],
    );
    await reveal(game);

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();

    // Only the app bar names the deck; the reveal card adds no origin line.
    expect(find.text('Rock & Pop Classics'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('with several decks the app bar counts them', (tester) async {
    usePhoneScreen(tester);
    final game = buildGame(
      categories: [
        escCategory,
        SongCategory(
          id: 'rock_pop',
          name: 'Rock & Pop Classics',
          description: '',
          songs: const [Song(title: 'A', artist: 'X', year: 1999)],
        ),
      ],
    );

    await tester.pumpWidget(wrap(game));
    await tester.pumpAndSettle();

    expect(find.text('2 categories'), findsOneWidget);
  });
}
