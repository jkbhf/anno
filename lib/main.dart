import 'dart:async';

import 'package:flutter/material.dart';

import 'data/game_store.dart';
import 'data/music_service_store.dart';
import 'data/roster_store.dart';
import 'data/song_repository.dart';
import 'data/year_database.dart';
import 'models/song_category.dart';
import 'music/music_service.dart';
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
  final service = await MusicServiceStore.load();

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
      service: service,
    ),
  );
}

class PlayApp extends StatefulWidget {
  const PlayApp({
    required this.years,
    required this.categories,
    required this.spotify,
    this.service = MusicService.spotify,
    this.savedGame,
    this.roster = const [],
    super.key,
  });

  final YearDatabase years;
  final List<SongCategory> categories;
  final SpotifySession spotify;

  /// The service picked on this device last time, from [MusicServiceStore].
  final MusicService service;

  final SavedGame? savedGame;

  /// Names from the last game, prefilled into the setup screen.
  final List<String> roster;

  @override
  State<PlayApp> createState() => _PlayAppState();
}

class _PlayAppState extends State<PlayApp> {
  late final ValueNotifier<MusicService> _service = ValueNotifier(
    widget.service,
  );

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      years: widget.years,
      categories: widget.categories,
      spotify: widget.spotify,
      service: _service,
      child: MaterialApp(
        title: 'Anno',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: SetupScreen(savedGame: widget.savedGame, roster: widget.roster),
      ),
    );
  }
}
