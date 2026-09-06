import 'dart:async';

import 'package:flutter/material.dart';

import 'data/game_store.dart';
import 'data/roster_store.dart';
import 'data/song_repository.dart';
import 'data/year_database.dart';
import 'models/song_category.dart';
import 'music/spotify_session.dart';
import 'ui/app_scope.dart';
import 'ui/setup_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final years = await YearDatabase.load();
  final categories = await SongRepository.loadAll();
  final savedGame = await GameStore.load();
  final roster = await RosterStore.load();

  // Picks a login back up - either the redirect the browser just came back
  // with, or a token from an earlier visit. Not awaited: the game starts
  // without Spotify, and the setup screen shows the connection catching up.
  final spotify = createSpotifySession();
  unawaited(spotify.restore());

  runApp(
    PlayApp(
      years: years,
      categories: categories,
      savedGame: savedGame,
      roster: roster,
      spotify: spotify,
    ),
  );
}

class PlayApp extends StatelessWidget {
  const PlayApp({
    required this.years,
    required this.categories,
    required this.spotify,
    this.savedGame,
    this.roster = const [],
    super.key,
  });

  final YearDatabase years;
  final List<SongCategory> categories;
  final SpotifySession spotify;
  final SavedGame? savedGame;

  /// Names from the last game, prefilled into the setup screen.
  final List<String> roster;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      years: years,
      categories: categories,
      spotify: spotify,
      child: MaterialApp(
        title: 'Play',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: SetupScreen(savedGame: savedGame, roster: roster),
      ),
    );
  }
}
