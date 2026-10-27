import 'dart:async';

import 'package:flutter/material.dart';

import 'data/camera_facing_store.dart';
import 'data/game_store.dart';
import 'data/music_service_store.dart';
import 'data/playback_device_store.dart';
import 'data/roster_store.dart';
import 'data/song_repository.dart';
import 'data/spotify_sdk_store.dart';
import 'data/year_database.dart';
import 'models/song_category.dart';
import 'music/music_service.dart';
import 'music/spotify_session.dart';
import 'sync/tv_link.dart';
import 'ui/app_scope.dart';
import 'ui/route_observer.dart';
import 'ui/setup_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final years = await YearDatabase.load();
  final categories = await SongRepository.loadAll();
  final savedGame = await GameStore.load();
  final roster = await RosterStore.load();
  final service = await MusicServiceStore.load();
  // Into memory rather than into a widget: a scanner controller is built
  // where there is nothing to await, so the side it opens on has to be
  // readable there.
  await CameraFacingStore.preload();
  // Same reason: the session reads it while it is handing a song over.
  await PlaybackDeviceStore.preload();
  // createSpotifySession below decides which player a phone starts with.
  await SpotifySdkStore.preload();

  // Picks a login back up - either the redirect the browser just came back
  // with, or a token from an earlier visit. Not awaited: the game starts
  // without Spotify, and the setup screen shows the connection catching up.
  final spotify = createSpotifySession();
  unawaited(spotify.restore());

  // Nothing is connected until somebody pairs: the line is built here only
  // because it has to outlive the screens that use it.
  final link = TvLink();

  runApp(
    PlayApp(
      years: years,
      categories: categories,
      savedGame: savedGame,
      roster: roster,
      spotify: spotify,
      link: link,
      service: service,
    ),
  );
}

class PlayApp extends StatefulWidget {
  const PlayApp({
    required this.years,
    required this.categories,
    required this.spotify,
    required this.link,
    this.service = MusicService.spotify,
    this.savedGame,
    this.roster = const [],
    super.key,
  });

  final YearDatabase years;
  final List<SongCategory> categories;
  final SpotifySession spotify;

  /// The line to a television, see [TvLink].
  final TvLink link;

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
      link: widget.link,
      service: _service,
      child: MaterialApp(
        title: 'Anno',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        navigatorObservers: [appRouteObserver],
        home: SetupScreen(savedGame: widget.savedGame, roster: widget.roster),
      ),
    );
  }
}
