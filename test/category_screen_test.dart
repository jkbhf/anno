// A companion deck covers only part of the century, so on its own it would
// answer most cards with nothing. The rule lives in `canCarryGame`; these
// tests pin both halves of it - the deck may be picked, but not alone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anno/data/year_database.dart';
import 'package:anno/models/player.dart';
import 'package:anno/models/song.dart';
import 'package:anno/models/song_category.dart';
import 'package:anno/music/spotify_session.dart';
import 'package:anno/ui/app_scope.dart';
import 'package:anno/ui/category_screen.dart';
import 'package:anno/ui/theme.dart';

SongCategory deck(String id, String name, {bool needsCompanion = false}) =>
    SongCategory(
      id: id,
      name: name,
      description: '',
      needsCompanion: needsCompanion,
      songs: [Song(year: 2016, title: 'A', artist: 'B')],
    );

final full = deck('esc', 'ESC');
final companion = deck('kpop', 'K-Pop', needsCompanion: true);
final empty = SongCategory(
  id: 'rock_pop',
  name: 'Rock & Pop',
  description: '',
  songs: const [],
);

Widget wrap(List<SongCategory> categories) => AppScope(
  years: YearDatabase.inMemory(),
  categories: categories,
  spotify: NoSpotifySession(),
  child: MaterialApp(
    theme: buildTheme(),
    home: CategoryScreen(
      players: [GamePlayer(name: 'Jakob')],
      targetScore: 10,
    ),
  ),
);

bool startEnabled(WidgetTester tester) => tester
    .widget<FilledButton>(find.widgetWithText(FilledButton, 'Start'))
    .onPressed !=
    null;

void main() {
  group('canCarryGame', () {
    test('a full deck carries a game, on its own too', () {
      expect(canCarryGame([full]), isTrue);
      expect(canCarryGame([full, companion]), isTrue);
    });

    test('a companion deck alone does not', () {
      expect(canCarryGame([companion]), isFalse);
      expect(canCarryGame([companion, companion]), isFalse);
    });

    test('nothing selected does not', () {
      expect(canCarryGame(const <SongCategory>[]), isFalse);
    });

    test('an empty deck cannot stand in for the full one', () {
      expect(canCarryGame([empty]), isFalse);
      expect(canCarryGame([empty, companion]), isFalse);
    });
  });

  testWidgets('a companion deck can be picked but not started alone', (
    tester,
  ) async {
    await tester.pumpWidget(wrap([full, companion]));

    await tester.tap(find.text('K-Pop'));
    await tester.pump();

    expect(startEnabled(tester), isFalse);
    expect(
      find.textContaining('pick another deck to go with it'),
      findsOneWidget,
    );
  });

  testWidgets('adding a full deck to it starts the game', (tester) async {
    await tester.pumpWidget(wrap([full, companion]));

    await tester.tap(find.text('K-Pop'));
    await tester.pump();
    await tester.tap(find.text('ESC'));
    await tester.pump();

    expect(
      tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Start with 2 categories'),
              )
              .onPressed !=
          null,
      isTrue,
    );
    expect(find.textContaining('pick another deck'), findsNothing);
  });

  testWidgets('dropping the full deck again disables Start', (tester) async {
    await tester.pumpWidget(wrap([full, companion]));

    await tester.tap(find.text('ESC'));
    await tester.pump();
    await tester.tap(find.text('K-Pop'));
    await tester.pump();
    await tester.tap(find.text('ESC'));
    await tester.pump();

    expect(startEnabled(tester), isFalse);
  });

  testWidgets('the card says the deck needs a second one', (tester) async {
    await tester.pumpWidget(wrap([full, companion]));

    expect(find.textContaining('only with another deck'), findsOneWidget);
  });

  testWidgets('with nothing picked Start is off and says nothing', (
    tester,
  ) async {
    await tester.pumpWidget(wrap([full, companion]));

    expect(startEnabled(tester), isFalse);
    expect(find.textContaining('pick another deck'), findsNothing);
  });
}
