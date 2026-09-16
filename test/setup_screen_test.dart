// The dialogs are where controller lifetimes go wrong: `showDialog` completes
// on pop, but the route keeps rebuilding through its exit animation.
// `pumpAndSettle` runs that animation, so a controller disposed too early
// throws here.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anno/data/game_store.dart';
import 'package:anno/data/year_database.dart';
import 'package:anno/models/player.dart';
import 'package:anno/models/song.dart';
import 'package:anno/models/song_category.dart';
import 'package:anno/music/music_service.dart';
import 'package:anno/music/spotify_session.dart';
import 'package:anno/ui/app_scope.dart';
import 'package:anno/ui/category_screen.dart';
import 'package:anno/ui/route_observer.dart';
import 'package:anno/ui/setup_screen.dart';
import 'package:anno/ui/theme.dart';

class FakeSession extends NoSpotifySession {
  FakeSession(this.state);

  final SpotifyConnection state;
  int disconnects = 0;

  @override
  SpotifyConnection get connection => state;

  @override
  Future<void> disconnect() async => disconnects++;
}

Widget wrap({
  SpotifySession? spotify,
  List<String> roster = const [],
  ValueNotifier<MusicService>? service,
}) => AppScope(
  years: YearDatabase.inMemory(),
  categories: [
    SongCategory(id: 'esc', name: 'ESC', description: '', songs: const []),
  ],
  spotify: spotify ?? NoSpotifySession(),
  service: service ?? ValueNotifier(MusicService.spotify),
  child: MaterialApp(
    theme: buildTheme(),
    home: SetupScreen(roster: roster),
  ),
);

/// The screen is a lazy list, and the lower half of it is not built until it
/// is scrolled to.
Future<void> scrollTo(WidgetTester tester, String text) =>
    tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );

void main() {
  testWidgets('the score target dialog survives its closing animation', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());

    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '7');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('7 points'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an implausible score target keeps the dialog open', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());

    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '0');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('At least 1 point'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a player does not touch a disposed controller', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());

    await tester.enterText(find.byType(TextField).first, 'Anna');
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty name fields do not become players', (tester) async {
    await tester.pumpWidget(wrap());

    // Two fields, one of them left empty on purpose.
    await tester.enterText(find.byType(TextField).first, 'Anna');
    await tester.pump();

    await scrollTo(tester, 'Continue to categories');
    await tester.tap(find.text('Continue to categories'));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryScreen), findsOneWidget);
    expect(find.text('1 player · to 10 points'), findsOneWidget);
  });

  testWidgets('without a single name the game cannot start', (tester) async {
    await tester.pumpWidget(wrap());

    await scrollTo(tester, 'Continue to categories');
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue to categories'),
    );

    expect(button.onPressed, isNull);
  });

  testWidgets('an unconnected Spotify asks for the login on a card', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(spotify: FakeSession(SpotifyConnection.disconnected)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect Spotify'), findsOneWidget);

    // Nothing to disconnect from yet - the menu holds the year database alone.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Year database'), findsOneWidget);
    expect(find.text('Disconnect Spotify'), findsNothing);
  });

  testWidgets('YouTube Music is picked here and outlives the screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final service = ValueNotifier(MusicService.spotify);
    await tester.pumpWidget(
      wrap(
        spotify: FakeSession(SpotifyConnection.disconnected),
        service: service,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connect Spotify'), findsOneWidget);

    await scrollTo(tester, 'YouTube Music');
    await tester.tap(find.text('YouTube Music'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await tester.pumpAndSettle();

    expect(service.value, MusicService.youtubeMusic);
    // No point logging in to a service this device does not play in.
    expect(find.text('Connect Spotify'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('music.service'), 'youtubeMusic');
  });

  testWidgets('a connected Spotify is a menu entry, not a card', (
    tester,
  ) async {
    final session = FakeSession(SpotifyConnection.ready);
    await tester.pumpWidget(wrap(spotify: session));
    await tester.pumpAndSettle();

    // The card is gone - a working connection has nothing to announce.
    expect(find.text('Connect Spotify'), findsNothing);
    expect(find.text('Play in the app'), findsNothing);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Year database'), findsOneWidget);

    await tester.tap(find.text('Disconnect Spotify'));
    await tester.pumpAndSettle();

    expect(session.disconnects, 1);
  });

  testWidgets('without a session only the year database is in the menu', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Connect Spotify'), findsNothing);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Year database'), findsOneWidget);
    expect(find.text('Disconnect Spotify'), findsNothing);
  });

  testWidgets('the names of the last group are already in the fields', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(roster: const ['Anna', 'Ben', 'Cleo']));
    await tester.pumpAndSettle();

    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Ben'), findsOneWidget);
    expect(find.text('Cleo'), findsOneWidget);
    // Three names, three fields - no empty leftovers underneath.
    expect(find.byType(TextField), findsNWidgets(3));
    // And the game can go on straight away - the button is live without a
    // single keystroke.
    await scrollTo(tester, 'Continue to categories');
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue to categories'),
    );
    expect(button.onPressed, isNotNull);
  });

  group('a game in progress', () {
    // With a song: a saved game on decks without any is not offered at all.
    final esc = SongCategory(
      id: 'esc',
      name: 'ESC',
      description: '',
      songs: const [
        Song(title: 'A', artist: 'X', year: 2005, spotifyTrackId: 'a'),
      ],
    );
    final saved = SavedGame(
      players: [GamePlayer(name: 'Anna', score: 4)],
      categoryIds: const ['esc'],
      targetScore: 10,
    );

    Widget withObserver({SavedGame? savedGame}) => AppScope(
      years: YearDatabase.inMemory(),
      categories: [esc],
      spotify: NoSpotifySession(),
      service: ValueNotifier(MusicService.spotify),
      child: MaterialApp(
        theme: buildTheme(),
        navigatorObservers: [appRouteObserver],
        home: SetupScreen(savedGame: savedGame, roster: const ['Anna']),
      ),
    );

    testWidgets('is not overwritten by a new one without asking', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(withObserver(savedGame: saved));
      await tester.pumpAndSettle();

      await scrollTo(tester, 'Continue to categories');
      await tester.tap(find.text('Continue to categories'));
      await tester.pumpAndSettle();

      expect(find.text('Start a new game?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(CategoryScreen), findsNothing);
    });

    testWidgets('comes back to the start screen when it is left', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(withObserver());
      await tester.pumpAndSettle();
      expect(find.text('Game in progress'), findsNothing);

      // Somewhere above the start screen a game gets saved, then left.
      await GameStore.save(saved);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Text('game')),
        ),
      );
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.text('Game in progress'), findsOneWidget);
    });
  });

  testWidgets('a first-time group gets two empty fields', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Player 1'), findsOneWidget);
  });
}
