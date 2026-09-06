// The dialogs are where controller lifetimes go wrong: `showDialog` completes
// on pop, but the route keeps rebuilding through its exit animation.
// `pumpAndSettle` runs that animation, so a controller disposed too early
// throws here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anno/data/year_database.dart';
import 'package:anno/models/song_category.dart';
import 'package:anno/music/spotify_session.dart';
import 'package:anno/ui/app_scope.dart';
import 'package:anno/ui/category_screen.dart';
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

Widget wrap({SpotifySession? spotify, List<String> roster = const []}) =>
    AppScope(
      years: YearDatabase.inMemory(),
      categories: [
        SongCategory(id: 'esc', name: 'ESC', description: '', songs: const []),
      ],
      spotify: spotify ?? NoSpotifySession(),
      child: MaterialApp(
        theme: buildTheme(),
        home: SetupScreen(roster: roster),
      ),
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

    await tester.tap(find.text('Continue to categories'));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryScreen), findsOneWidget);
    expect(find.text('1 player · to 10 points'), findsOneWidget);
  });

  testWidgets('without a single name the game cannot start', (tester) async {
    await tester.pumpWidget(wrap());

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
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue to categories'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('a first-time group gets two empty fields', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Player 1'), findsOneWidget);
  });
}
