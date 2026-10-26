import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../data/game_store.dart';
import '../data/played_songs_store.dart';
import '../data/skipped_songs_store.dart';
import '../game/game_controller.dart';
import '../models/player.dart';
import '../models/song.dart';
import '../models/song_category.dart';
import '../music/in_app_launcher.dart';
import '../music/lyrics.dart';
import '../music/music_service.dart';
import '../music/spotify_session.dart';
import '../music/youtube_music_launcher.dart';
import 'app_scope.dart';
import 'category_screen.dart';
import 'centered_body.dart';
import 'countdown_screen.dart';
import 'haptics/haptics.dart';
import 'lyrics_sheet.dart';
import 'scanner_screen.dart';
import 'song_progress_bar.dart';
import 'theme.dart';
import 'wake_lock/wake_lock.dart';
import 'year_database_screen.dart';

/// Starts a game and cleans the controller up afterwards.
Future<void> openGame(
  BuildContext context, {
  required List<SongCategory> categories,
  required List<GamePlayer> players,
  required int targetScore,
  Map<String, int> weights = const {},
  List<String> played = const [],
}) async {
  final scope = AppScope.of(context);
  final service = scope.service.value;
  final spotify = scope.spotify;
  // Read per game, not once at startup: the game before this one tonight is
  // part of what the next one should not play again.
  final playedBefore = await PlayedSongsStore.load();
  final skippedBefore = await SkippedSongsStore.load();
  final inApp = InAppSpotifyLauncher(spotify);
  final controller = GameController(
    players: players,
    categories: categories,
    years: scope.years,
    weights: weights,
    targetScore: targetScore,
    persist: GameStore.save,
    discard: GameStore.clear,
    stopMusic: spotify.stop,
    onPlayedChanged: (keys) => unawaited(PlayedSongsStore.save(keys)),
    played: {...playedBefore, ...played},
    onSkippedChanged: (keys) => unawaited(SkippedSongsStore.save(keys)),
    skipped: skippedBefore,
    service: service,
    launcher: switch (service) {
      MusicService.spotify => inApp,
      MusicService.youtubeMusic => const YouTubeMusicLauncher(),
    },
    linkLauncher: switch (service) {
      MusicService.spotify => inApp.fallback,
      MusicService.youtubeMusic => const YouTubeMusicLauncher(),
    },
  );
  await GameStore.save(controller.snapshot);
  if (!context.mounted) {
    controller.dispose();
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => GameScreen(controller: controller)),
  );
  controller.dispose();
}

/// Whether the three seconds before a round run - everywhere but in a round
/// that plays in the Spotify player of this tab. See `_runCountdown`.
@visibleForTesting
bool needsCountdown(MusicService service, {required bool sessionReady}) =>
    !(service == MusicService.spotify && sessionReady);

/// Whether the round gets the wide layout: a stage for the room and a column
/// beside it for whoever runs the game - a laptop on a projector, a tablet on
/// its side. A phone keeps its one column even turned, where the stage would
/// be a strip.
///
/// The height floor is what tells a turned phone from a small laptop: a big
/// phone sideways is ~930x430 and clears the width on its own.
bool isWideScreen(Size size) =>
    size.width >= 900 &&
    size.height >= 600 &&
    size.width >= size.height * 1.2;

/// The main screen: scan, listen, reveal, hand out points.
class GameScreen extends StatefulWidget {
  const GameScreen({
    required this.controller,
    this.lyrics,
    this.camera,
    super.key,
  });

  final GameController controller;

  /// What reads the card, on its own page or in the side column of the wide
  /// layout. Null is the device camera; a test hands in a stand-in.
  final CameraBuilder? camera;

  /// Where the words behind the lyrics button come from. Null is LRCLIB.
  final LyricsSource? lyrics;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  GameController get _game => widget.controller;

  /// Blocks the scan flow while one is already running.
  bool _busy = false;

  RoundPhase _lastPhase = RoundPhase.idle;

  /// Only needed to silence the in-app player; the screen itself reads the
  /// session out of the scope where it draws with it.
  SpotifySession? _spotify;

  /// The camera open in the side column of the wide layout, waiting for a
  /// card. Null while it is closed. See [_scanCode].
  Completer<String?>? _inlineScan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastPhase = _game.phase;
    _game.addListener(_onPhaseChanged);
    unawaited(WakeLock.hold());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final spotify = AppScope.of(context).spotify;
    if (!identical(spotify, _spotify)) {
      _spotify?.removeListener(_onSessionChanged);
      _spotify = spotify..addListener(_onSessionChanged);
    }
  }

  @override
  void dispose() {
    // Lets the round that waits on it run out, instead of hanging on.
    _inlineScan?.complete();
    _inlineScan = null;
    unawaited(WakeLock.release());
    _spotify?.removeListener(_onSessionChanged);
    unawaited(_spotify?.stop());
    _game.removeListener(_onPhaseChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Spotify took the song and then could not play it. The round has to hear
  /// about that, or it sits there in silence without its link button.
  void _onSessionChanged() {
    if (_spotify?.playbackError != null) _game.playbackFailedInApp();
  }

  /// The reveal can arrive without anybody touching the screen - the app is
  /// coming back from Spotify. A buzz says the year is up.
  void _onPhaseChanged() {
    final phase = _game.phase;
    if (phase == RoundPhase.revealed && _lastPhase != RoundPhase.revealed) {
      Haptics.reveal();
    }
    // A song played in the app runs through the guessing and the scoring and
    // ends with the round - not at the reveal, where the points are still
    // being handed out.
    if (phase != _lastPhase &&
        (phase == RoundPhase.idle || phase == RoundPhase.finished)) {
      unawaited(_spotify?.stop());
    }
    _lastPhase = phase;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The browser drops the lock whenever the tab was hidden - every trip
      // to Spotify and back.
      unawaited(WakeLock.hold());
      _game.onAppResumed();
    }
  }

  /// The words of the running song, over the round. While the room guesses
  /// the sheet leaves the name off; in a round played in this tab the text
  /// follows the song.
  void _showLyrics() {
    final song = _game.currentSong;
    if (song == null) return;
    unawaited(
      showLyricsSheet(
        context,
        song: song,
        source: widget.lyrics ?? sharedLyrics,
        session: _game.playingInApp ? _spotify : null,
        hideSong: !_game.isRevealed,
      ),
    );
  }

  /// Asks for the words while the countdown runs, so the sheet has them when
  /// somebody taps. A failure here is no matter: the sheet asks again.
  void _prefetchLyrics() {
    final song = _game.currentSong;
    if (song == null) return;
    unawaited(
      (widget.lyrics ?? sharedLyrics)
          .find(song)
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }

  /// Opens the camera and returns the scanned code, or null when it was
  /// closed without one.
  ///
  /// On a wide screen the camera opens small, in the side column, instead of
  /// as a page over everything: the room keeps the stage - the year that was
  /// just revealed, the scores - while the next card is held up.
  Future<String?> _scanCode() async {
    if (_busy) return null;
    // Still inside the tap: a mobile browser grants sound from here, not from
    // the countdown three seconds later.
    if (_game.service == MusicService.spotify) {
      unawaited(_spotify?.prepare() ?? Future<void>.value());
    }
    _busy = true;
    try {
      if (isWideScreen(MediaQuery.sizeOf(context))) {
        final scan = Completer<String?>();
        setState(() => _inlineScan = scan);
        return await scan.future;
      }
      return await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => ScannerScreen(camera: widget.camera),
        ),
      );
    } finally {
      _busy = false;
    }
  }

  /// Closes the camera in the side column, with the code it read or without.
  void _closeInlineScan([String? code]) {
    final scan = _inlineScan;
    if (scan == null) return;
    setState(() => _inlineScan = null);
    scan.complete(code);
  }

  Future<void> _startRound() async {
    final code = await _scanCode();
    if (!mounted || code == null) return;
    await _handleCode(code);
  }

  Future<void> _handleCode(String code) async {
    var outcome = _game.scan(code);

    if (outcome == ScanOutcome.unknownCode) {
      final year = await askForYear(context, code: code);
      if (!mounted || year == null) return;
      await AppScope.of(context).years.setYear(code, year);
      if (!mounted) return;
      outcome = _game.scan(code);
    }

    switch (outcome) {
      case ScanOutcome.unknownCode:
        return;
      case ScanOutcome.noSongForYear:
        final year = _game.currentYear!;
        _game.cancelRound();
        // The year can be there and still have nothing this service plays.
        final onOtherService = _game.categories.any(
          (category) => category.songsForYear(year).isNotEmpty,
        );
        await _showNote(
          'No song for $year',
          onOtherService
              ? 'Nothing for that year is on ${_game.service.label} - draw '
                    'another card.'
              // A deck on its own is often one that only covers part of the
              // century, so the span is what the room needs to hear.
              : _game.categories.length == 1
              ? '${_game.categories.single.name} covers '
                    '${_game.categories.single.yearSpan} - draw another card.'
              : 'None of the chosen categories has an entry for that year '
                    'yet. Draw another card or fill in the catalog.',
        );
        return;
      case ScanOutcome.started:
        _prefetchLyrics();
        if (!await _runCountdown()) {
          _game.cancelRound();
          return;
        }
        await _game.startPlayback();
    }
  }

  /// Swaps the song nobody knows for another one of the year, and hands that
  /// one over the way a scan would.
  Future<void> _redraw() async {
    if (_busy) return;
    if (!_game.redraw()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other song for this year.')),
      );
      return;
    }
    await _handOverAgain();
  }

  /// Brings the song back that the last swap took away.
  Future<void> _undoRedraw() async {
    if (_busy || !_game.undoRedraw()) return;
    await _handOverAgain();
  }

  /// Hands the round's new song over after a swap or its undo.
  Future<void> _handOverAgain() async {
    Haptics.tick();
    _prefetchLyrics();
    _busy = true;
    try {
      if (!await _runCountdown()) {
        _game.cancelRound();
        return;
      }
      await _game.startPlayback();
    } finally {
      _busy = false;
    }
  }

  /// The three seconds between the scan and the song. False when the round was
  /// cancelled on them.
  ///
  /// Only the handover needs it. The song then comes out of Spotify or YouTube
  /// Music, a tab or an app away, and it starts while the room is still
  /// looking at the phone - the countdown is what puts everybody on the same
  /// beat. A song played in this tab has no such gap: it is there as soon as
  /// the round screen is, so the countdown would only hold the music up.
  ///
  /// This is the one place that asks the session instead of the launch, and it
  /// has to: nothing has been handed over yet, so there is no launch to ask.
  /// Being wrong here costs a countdown, never a round - a ready session that
  /// refuses the track still falls back to the link, and the round runs on.
  ///
  /// A connected session is no reason to skip it on YouTube Music: that game
  /// never plays through the session, so the song always goes out by link.
  Future<bool> _runCountdown() async {
    final countdown = needsCountdown(
      _game.service,
      sessionReady: _spotify?.isReady ?? false,
    );
    if (!countdown) return true;
    final ran = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const CountdownScreen()),
    );
    return mounted && (ran ?? false);
  }

  /// Ends the round and goes straight back to the camera - the scan is the
  /// only thing that happens next anyway.
  ///
  /// The round is only cleared once the camera closes again. Ending it first
  /// would drop the screen back to the big scan button for the length of the
  /// route animation, and that flash is exactly what this avoids.
  ///
  /// Backing out of the camera keeps the reveal: whoever opened it may still
  /// want to hand out a point, or simply tapped too early.
  Future<void> _nextRound() async {
    if (_busy) return;

    if (_game.winners.isNotEmpty) {
      _game.nextRound();
      return;
    }

    final code = await _scanCode();
    if (!mounted || code == null) return;
    _game.nextRound();
    await _handleCode(code);
  }

  Future<void> _showNote(String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(String value) async {
    switch (value) {
      case 'reset':
        final ok = await _confirm(
          'Reset scores?',
          'Everyone starts back at 0.',
        );
        if (ok) _game.resetScores();
      case 'years':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const YearDatabaseScreen()),
        );
      case 'category':
        final ok = await _confirm(
          'Change categories?',
          'The scores stay, and the game goes on with the new choice.',
        );
        if (!ok || !mounted) return;
        // Straight to the choice, from wherever the game was opened: a resumed
        // game has no category screen underneath it to go back to.
        final navigator = Navigator.of(context);
        final players = _game.players;
        final target = _game.targetScore;
        final played = _game.played.toList();
        final selected = {for (final c in _game.categories) c.id};
        final weights = {
          for (final c in _game.categories) c.id: _game.weightOf(c),
        };
        navigator.popUntil((route) => route.isFirst);
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => CategoryScreen(
                players: players,
                targetScore: target,
                played: played,
                initialSelection: selected,
                initialWeights: weights,
              ),
            ),
          ),
        );
      case 'new':
        final ok = await _confirm(
          'New game?',
          'The running game will be discarded.',
        );
        if (!ok || !mounted) return;
        await GameStore.clear();
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// The back button, the browser's included. A running game is saved, so
  /// leaving it loses nothing - but a stray swipe should not end the evening
  /// without anyone noticing.
  Future<void> _onBack(bool didPop) async {
    if (didPop) return;
    if (_game.phase != RoundPhase.finished) {
      final ok = await _confirm(
        'Leave the game?',
        'It stays saved and can be resumed from the start screen.',
      );
      if (!ok || !mounted) return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onBack(didPop),
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    final wide = isWideScreen(MediaQuery.sizeOf(context));
    // A window made narrow while the camera waits in the side column has no
    // side column left to show it in.
    if (!wide && _inlineScan != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _closeInlineScan();
      });
    }

    return ListenableBuilder(
      listenable: _game,
      builder: (context, _) {
        // The finish has one thing to say, and says it the same everywhere.
        final body = wide && _game.phase != RoundPhase.finished
            ? _wideBody(context)
            : CenteredBody(child: _body(context));
        return Scaffold(
          appBar: AppBar(
            // On the wide layout the only thing that scrolls is the words, in
            // their own box - no page goes under the bar for it to tint over.
            notificationPredicate: wide
                ? (_) => false
                : defaultScrollNotificationPredicate,
            title: Text(
              _game.categories.length == 1
                  ? _game.categories.single.name
                  : '${_game.categories.length} categories',
            ),
            actions: [
              PopupMenuButton<String>(
                onSelected: _onMenu,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'reset', child: Text('Reset scores')),
                  PopupMenuItem(
                    value: 'category',
                    child: Text('Change category'),
                  ),
                  PopupMenuItem(value: 'years', child: Text('Year database')),
                  PopupMenuItem(value: 'new', child: Text('New game')),
                ],
              ),
            ],
          ),
          body: SafeArea(child: body),
        );
      },
    );
  }

  /// The round on a wide screen, see [_WideRound].
  Widget _wideBody(BuildContext context) {
    // As on the phone: the countdown is up over the screen, or the song is
    // starting within the frame.
    if (_game.phase == RoundPhase.countdown) return const SizedBox.shrink();
    return _WideRound(
      game: _game,
      spotify: AppScope.of(context).spotify,
      lyrics: widget.lyrics ?? sharedLyrics,
      camera: _inlineScan == null
          ? null
          : widget.camera ?? (context, onCode) => ScannerView(onCode: onCode),
      onCode: _closeInlineScan,
      onCloseCamera: _closeInlineScan,
      onScan: _startRound,
      onNextRound: _nextRound,
      onRedraw: _redraw,
      onUndoRedraw: _undoRedraw,
    );
  }

  Widget _body(BuildContext context) {
    switch (_game.phase) {
      case RoundPhase.idle:
        return _IdleBody(game: _game, onScan: _startRound);
      case RoundPhase.countdown:
        // Either the countdown route is up over this screen, or the song is
        // already starting - a single frame in the in-app case. Drawing
        // anything here would only flicker behind the one or the other.
        return const SizedBox.shrink();
      case RoundPhase.playing:
        return _PlayingBody(
          game: _game,
          spotify: AppScope.of(context).spotify,
          onRedraw: _redraw,
          onUndoRedraw: _undoRedraw,
          onLyrics: _showLyrics,
        );
      case RoundPhase.revealed:
        return _RevealBody(
          game: _game,
          onNextRound: _nextRound,
          onLyrics: _showLyrics,
        );
      case RoundPhase.finished:
        return _FinishedBody(
          game: _game,
          onUndo: _game.undoFinish,
          onRematch: _game.resetScores,
          onHome: () async {
            await GameStore.clear();
            if (!context.mounted) return;
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        );
    }
  }
}

/// Fits the whole body on the screen, shrinking it rather than scrolling.
///
/// The phone is passed around a table and tapped by whoever is holding it, so
/// a screen that has to be scrolled first is a screen where the tile you want
/// is not where you left it. With two players there is room to spare, with
/// eight there is not - and then everything gets smaller together instead of
/// half of it going off the bottom edge.
class _FitBody extends StatelessWidget {
  const _FitBody({
    required this.child,
    this.center = true,
    this.padding = const EdgeInsets.fromLTRB(20, 24, 20, 28),
  });

  final Widget child;

  /// Centring suits a screen with one thing on it. The round has a stack of
  /// blocks that read top down, so it starts at the top and lets any space
  /// left over fall below the last button.
  final bool center;

  /// The margin of a whole screen. A panel of the wide layout brings its own.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final alignment = center ? Alignment.center : Alignment.topCenter;

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: alignment,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignment,
            // A FittedBox hands its child all the room in the world, so the
            // width has to come from here - otherwise a stretched column has
            // nothing to stretch to.
            child: SizedBox(
              width: constraints.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [child],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A heading with the score target beside it.
///
/// The target belongs on a screen once, not on every tile: eight tiles each
/// repeating "/ 10" is noise, and the number cannot change during a game.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.targetScore});

  final String title;
  final int targetScore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
        const SizedBox(width: 8),
        Text(
          '/ $targetScore',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _IdleBody extends StatelessWidget {
  const _IdleBody({required this.game, required this.onScan});

  final GameController game;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _FitBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: InkWell(
              onTap: onScan,
              borderRadius: BorderRadius.circular(140),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primaryContainer,
                ),
                child: Icon(
                  Icons.qr_code_scanner,
                  size: 96,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Scan a card',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            'QR code on the front of the card',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 56),
          _SectionHeading(title: 'Scores', targetScore: game.targetScore),
          const SizedBox(height: 16),
          _PlayerGrid(game: game),
        ],
      ),
    );
  }
}

class _PlayingBody extends StatelessWidget {
  const _PlayingBody({
    required this.game,
    required this.spotify,
    required this.onRedraw,
    required this.onUndoRedraw,
    required this.onLyrics,
  });

  final GameController game;
  final SpotifySession spotify;
  final VoidCallback onRedraw;
  final VoidCallback onUndoRedraw;
  final VoidCallback onLyrics;

  @override
  Widget build(BuildContext context) {
    return _FitBody(
      center: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RevealSlot(
            onReveal: game.reveal,
            inApp: _looksInApp(game, spotify),
            service: game.service,
          ),
          const SizedBox(height: 20),
          _SongControls(
            game: game,
            spotify: spotify,
            onRedraw: onRedraw,
            onUndoRedraw: onUndoRedraw,
            onLyrics: onLyrics,
          ),
          const SizedBox(height: 32),
          _SectionHeading(title: 'Scores', targetScore: game.targetScore),
          const SizedBox(height: 16),
          // The same tiles as the reveal, but inert: points are handed out
          // once the year is up, not while the group is still guessing.
          _PlayerGrid(game: game),
        ],
      ),
    );
  }
}

/// Whether the playing screen is laid out for a song in the tab.
///
/// The launch decides, but a swap hands the song over again, and until that
/// launch answers the round is not in the tab: the bar would go, the reveal
/// card would change its text, and the whole screen below them would jump and
/// jump back. So while a launch is out on a session that plays here, the
/// screen keeps the in-tab layout. Only the layout - what the round does still
/// follows [GameController.playingInApp].
bool _looksInApp(GameController game, SpotifySession spotify) =>
    game.playingInApp ||
    (game.launching && game.service == MusicService.spotify && spotify.isReady);

/// What can be done with the song while the room guesses: move around in it,
/// get back to the service, swap it for one somebody knows.
class _SongControls extends StatelessWidget {
  const _SongControls({
    required this.game,
    required this.spotify,
    required this.onRedraw,
    required this.onUndoRedraw,
    this.onLyrics,
  });

  final GameController game;
  final SpotifySession spotify;
  final VoidCallback onRedraw;
  final VoidCallback onUndoRedraw;

  /// Null where the words are up anyway - the stage of the wide layout.
  final VoidCallback? onLyrics;

  @override
  Widget build(BuildContext context) {
    // The pause button and the "Premium needed" line both come out of the
    // session, which changes without the game noticing.
    return ListenableBuilder(
      listenable: spotify,
      builder: (context, _) => _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final message = game.launchMessage;
    final lyrics = onLyrics;

    // Playing in the app is the good case: nobody leaves the game, so there is
    // nothing to come back from and the year waits for the button.
    //
    // What the session says about itself is not the question - it can be ready
    // and still have refused the track, and then the song went out by link.
    // The round has to follow what actually happened, or it drops the button
    // that is the only way back to a popup the browser swallowed.
    final inApp = game.playingInApp;

    // On the web a blocked popup looks exactly like a successful one, so the
    // way to the service stays reachable by hand.
    final openButton = kIsWeb
        ? Center(
            child: TextButton.icon(
              onPressed: game.reopen,
              icon: const Icon(Icons.open_in_new),
              label: Text('Open in ${game.service.label}'),
            ),
          )
        : null;

    // The bar's room while the launch is still out, see [_looksInApp]. Once
    // it has answered the room follows it: a link round has no bar, hidden or
    // not.
    final keepBarRoom = !inApp && _looksInApp(game, spotify);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (inApp)
          SongProgressBar(session: spotify)
        else if (keepBarRoom)
          Stack(
            alignment: Alignment.center,
            children: [
              Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: SongProgressBar(session: spotify),
              ),
              ?openButton,
            ],
          )
        else
          ?openButton,
        if (lyrics != null)
          Center(
            child: TextButton.icon(
              onPressed: lyrics,
              icon: const Icon(Icons.lyrics_outlined),
              label: const Text('Lyrics'),
            ),
          ),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        // For the song nobody in the room knows - that round is a coin flip.
        if (game.canRedraw) ...[
          const SizedBox(height: 4),
          // The undo sits in the same row, so it comes and goes without
          // moving anything.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: TextButton.icon(
                  onPressed: onRedraw,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Nobody knows it? Draw another'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Visibility(
                visible: game.canUndoRedraw,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: IconButton(
                  tooltip: 'Back to the last song',
                  onPressed: onUndoRedraw,
                  icon: const Icon(Icons.undo),
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Sits where the song card will be, in the same shape and size, so revealing
/// swaps one for the other instead of rearranging the screen.
///
/// The whole panel is the button. The phone is being passed around a table and
/// tapped by whoever is holding it, so the target is the card, not a control
/// inside it - the pill only says what the tap does.
///
/// Deliberately in theme colours: the card it stands in for is tinted by the
/// decade, and that tint would hand the room the answer.
class _RevealSlot extends StatelessWidget {
  const _RevealSlot({
    required this.onReveal,
    required this.inApp,
    required this.service,
    this.wide = false,
  });

  final VoidCallback onReveal;
  final bool inApp;
  final MusicService service;

  /// A banner across the top of the stage instead of a card: the words below
  /// it need the height more than the slot does.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: theme.colorScheme.outlineVariant, width: 2),
    );

    final icon = Icon(
      Icons.music_note,
      size: 56,
      color: theme.colorScheme.primary,
    );
    final title = Text(
      inApp ? 'The song is playing' : 'The song is playing in ${service.label}',
      textAlign: wide ? TextAlign.start : TextAlign.center,
      style: wide
          ? theme.textTheme.headlineMedium
          : theme.textTheme.titleMedium,
    );
    final hint = Text(
      inApp
          ? 'Everyone guesses the year.'
          : 'Everyone guesses the year. Coming back to the app reveals it too.',
      textAlign: wide ? TextAlign.start : TextAlign.center,
      style: (wide ? theme.textTheme.titleMedium : theme.textTheme.bodySmall)
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
    final pill = Container(
      padding: wide
          ? const EdgeInsets.symmetric(horizontal: 28, vertical: 16)
          : const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(100),
      ),
      // The label is the one thing here that cannot wrap, so on a narrow
      // phone - or with the text scaled up - it shrinks instead of running
      // over the edge.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_outlined,
              size: wide ? 26 : 20,
              color: theme.colorScheme.onPrimary,
            ),
            const SizedBox(width: 8),
            Text(
              'Reveal the year',
              style:
                  (wide
                          ? theme.textTheme.titleLarge
                          : theme.textTheme.labelLarge)
                      ?.copyWith(color: theme.colorScheme.onPrimary),
            ),
          ],
        ),
      ),
    );

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onReveal,
        child: wide
            ? _FitBody(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 20,
                ),
                child: Row(
                  children: [
                    icon,
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 6), hint],
                      ),
                    ),
                    const SizedBox(width: 24),
                    pill,
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 34),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(height: 16),
                    title,
                    const SizedBox(height: 6),
                    hint,
                    const SizedBox(height: 28),
                    pill,
                  ],
                ),
              ),
      ),
    );
  }
}

/// Where the song came from: the deck, and for a contest entry the country and
/// the rank it finished in.
///
/// The deck is named whenever it adds something - with several categories in
/// play it says which one was drawn, and for a contest entry it is what makes
/// the year on the card read as "the year of that contest".
String? _originLine(GameController game, Song? song) {
  if (song == null) return null;

  final parts = <String>[
    if (game.categories.length > 1 || song.isContestEntry)
      game.currentCategory?.name ?? '',
    if (song.country != null) song.country!,
    if (song.placeOrdinal != null) '${song.placeOrdinal} place',
  ]..removeWhere((part) => part.isEmpty);

  return parts.isEmpty ? null : parts.join('  ·  ');
}

void _givePoint(GameController game, GamePlayer player) {
  Haptics.point();
  game.addPoint(player);
}

void _takePoint(GameController game, GamePlayer player) {
  Haptics.undo();
  game.removePoint(player);
}

/// The answer: the year, tinted by its decade, with the song under it - or,
/// on the stage of the wide layout, beside it.
class _YearCard extends StatelessWidget {
  const _YearCard({required this.game, this.wide = false});

  final GameController game;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = game.currentSong;
    final year = game.currentYear ?? song?.year ?? 0;
    final accent = decadeColor(year);
    final align = wide ? TextAlign.start : TextAlign.center;

    final origin = switch (_originLine(game, song)) {
      final line? => Text(
        line,
        textAlign: align,
        style: (wide ? theme.textTheme.titleMedium : theme.textTheme.labelLarge)
            ?.copyWith(color: accent, letterSpacing: 0.4),
      ),
      null => null,
    };
    final yearText = Text(
      '$year',
      maxLines: 1,
      style: TextStyle(
        fontSize: wide ? 140 : 84,
        fontWeight: FontWeight.w800,
        height: 1,
        letterSpacing: wide ? -3 : -2,
        color: accent,
      ),
    );
    final name = [
      if (song != null) ...[
        Text(
          song.title,
          textAlign: align,
          style:
              (wide
                      ? theme.textTheme.displaySmall
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          song.artist,
          textAlign: align,
          style:
              (wide ? theme.textTheme.headlineSmall : theme.textTheme.bodyLarge)
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    ];

    final decoration = BoxDecoration(
      color: accent.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: accent, width: 2),
    );

    if (wide) {
      return DecoratedBox(
        decoration: decoration,
        child: _FitBody(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 20),
          child: Row(
            children: [
              yearText,
              const SizedBox(width: 40),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (origin != null) ...[origin, const SizedBox(height: 8)],
                    ...name,
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 34),
      decoration: decoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (origin != null) ...[origin, const SizedBox(height: 10)],
          // Scales down rather than wrapping: a broken year is the one thing
          // on this screen that must stay readable.
          FittedBox(fit: BoxFit.scaleDown, child: yearText),
          if (song != null) const SizedBox(height: 18),
          ...name,
        ],
      ),
    );
  }
}

class _RevealBody extends StatelessWidget {
  const _RevealBody({
    required this.game,
    required this.onNextRound,
    required this.onLyrics,
  });

  final GameController game;
  final VoidCallback onNextRound;
  final VoidCallback onLyrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _FitBody(
      center: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _YearCard(game: game),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: onLyrics,
              icon: const Icon(Icons.lyrics_outlined),
              label: const Text('Lyrics'),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeading(
            title: 'Who got it right?',
            targetScore: game.targetScore,
          ),
          const SizedBox(height: 4),
          Text(
            'Tap to give a point, long press to take one away.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _PlayerGrid(
            game: game,
            onTap: (player) => _givePoint(game, player),
            onLongPress: (player) => _takePoint(game, player),
          ),
          const SizedBox(height: 40),
          // Tall for the same reason the reveal panel is: the phone is being
          // handed on, and this is the tap that keeps the game moving.
          FilledButton.icon(
            onPressed: onNextRound,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              textStyle: theme.textTheme.titleMedium,
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Next round'),
          ),
        ],
      ),
    );
  }
}

class _PlayerGrid extends StatelessWidget {
  const _PlayerGrid({required this.game, this.onTap, this.onLongPress});

  final GameController game;

  /// Null outside the reveal: the same tiles then only report the score.
  final void Function(GamePlayer player)? onTap;
  final void Function(GamePlayer player)? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    final longPress = onLongPress;
    // Two columns hold four players comfortably. Beyond that a third column
    // keeps the grid at three rows instead of four - otherwise the whole body
    // gets scaled down until the names are too small to read across a table.
    final wide = game.players.length > 4;

    return GridView.count(
      crossAxisCount: wide ? 3 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: wide ? 12 : 16,
      crossAxisSpacing: wide ? 12 : 16,
      childAspectRatio: wide ? 0.95 : 1.45,
      children: [
        for (final player in game.players)
          _PlayerTile(
            player: player,
            targetScore: game.targetScore,
            onTap: tap == null ? null : () => tap(player),
            onLongPress: longPress == null ? null : () => longPress(player),
          ),
      ],
    );
  }
}

class _PlayerTile extends StatefulWidget {
  const _PlayerTile({
    required this.player,
    required this.targetScore,
    this.onTap,
    this.onLongPress,
    this.large = false,
  });

  final GamePlayer player;
  final int targetScore;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Sized for the stage, read across a room. The tile then shrinks what it
  /// holds rather than overflowing - eight of them in a row on a 720p
  /// projector are short.
  final bool large;

  @override
  State<_PlayerTile> createState() => _PlayerTileState();
}

class _PlayerTileState extends State<_PlayerTile> {
  /// A tap changes one digit somewhere on a screen four people are looking at.
  /// The flash is what tells the room which tile was hit.
  bool _flashing = false;

  void _flash() {
    setState(() => _flashing = true);
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _flashing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = widget.player;
    final reached = player.score >= widget.targetScore;
    final interactive = widget.onTap != null || widget.onLongPress != null;

    final background = _flashing
        ? theme.colorScheme.primary
        : reached
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = _flashing
        ? theme.colorScheme.onPrimary
        : reached
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.primary;

    final large = widget.large;
    final column = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          player.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: large
              ? theme.textTheme.titleLarge
              : theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        AnimatedScale(
          scale: _flashing ? 1.15 : 1,
          duration: const Duration(milliseconds: 120),
          child: Text(
            '${player.score}',
            style:
                (large
                        ? theme.textTheme.displayMedium
                        : theme.textTheme.displaySmall)
                    ?.copyWith(fontWeight: FontWeight.w700, color: foreground),
          ),
        ),
      ],
    );
    const padding = EdgeInsets.all(12);
    final content = large
        ? _FitBody(padding: padding, child: column)
        : Padding(padding: padding, child: column);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: interactive
          ? InkWell(
              onTap: () {
                _flash();
                widget.onTap?.call();
              },
              onLongPress: () {
                _flash();
                widget.onLongPress?.call();
              },
              child: content,
            )
          : content,
    );
  }
}

/// The round on a wide screen - a laptop on a projector, a tablet on its side.
///
/// Two halves for two audiences. The stage on the right is for the room: the
/// reveal, the words, the scores, sized to be read from the sofa. The column
/// on the left is for whoever runs the game: the camera opens there, small,
/// instead of as a page over everything, and the controls for the song sit
/// under it.
class _WideRound extends StatelessWidget {
  const _WideRound({
    required this.game,
    required this.spotify,
    required this.lyrics,
    required this.camera,
    required this.onCode,
    required this.onCloseCamera,
    required this.onScan,
    required this.onNextRound,
    required this.onRedraw,
    required this.onUndoRedraw,
  });

  final GameController game;
  final SpotifySession spotify;
  final LyricsSource lyrics;

  /// The camera while it is open, null while it is closed.
  final CameraBuilder? camera;
  final ValueChanged<String> onCode;
  final VoidCallback onCloseCamera;
  final VoidCallback onScan;
  final VoidCallback onNextRound;
  final VoidCallback onRedraw;
  final VoidCallback onUndoRedraw;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = (constraints.maxWidth * 0.28).clamp(300.0, 420.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: side,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 12, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 4 / 3,
                      child: _CameraSlot(
                        phase: game.phase,
                        camera: camera,
                        onCode: onCode,
                        onClose: onCloseCamera,
                        onScan: onScan,
                        onNextRound: onNextRound,
                      ),
                    ),
                    if (game.phase == RoundPhase.playing)
                      Expanded(
                        child: _FitBody(
                          center: false,
                          padding: const EdgeInsets.only(top: 20),
                          child: _SongControls(
                            game: game,
                            spotify: spotify,
                            onRedraw: onRedraw,
                            onUndoRedraw: onUndoRedraw,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _Stage(game: game, spotify: spotify, lyrics: lyrics),
            ),
          ],
        );
      },
    );
  }
}

/// The place in the side column where the camera opens.
///
/// Closed, it is the button for what the camera is needed for next: the first
/// card, or the next round once the year is out. The camera only runs while
/// it is asked for - kept running, it would read the card still lying in front
/// of it and start the next round before the points are handed out.
class _CameraSlot extends StatelessWidget {
  const _CameraSlot({
    required this.phase,
    required this.camera,
    required this.onCode,
    required this.onClose,
    required this.onScan,
    required this.onNextRound,
  });

  final RoundPhase phase;
  final CameraBuilder? camera;
  final ValueChanged<String> onCode;
  final VoidCallback onClose;
  final VoidCallback onScan;
  final VoidCallback onNextRound;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(24);

    final open = camera;
    if (open != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            open(context, onCode),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: 'Close the camera',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      );
    }

    final scheme = theme.colorScheme;
    final (icon, title, hint, onTap, background, foreground) = switch (phase) {
      RoundPhase.revealed => (
        Icons.arrow_forward,
        'Next round',
        'Opens the camera for the next card',
        onNextRound,
        scheme.primary,
        scheme.onPrimary,
      ),
      RoundPhase.playing => (
        Icons.qr_code_scanner,
        'Next card after the reveal',
        null,
        null,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      _ => (
        Icons.qr_code_scanner,
        'Scan a card',
        'Opens the camera here',
        onScan,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
    };

    return Material(
      color: background,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: _FitBody(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 56, color: foreground),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(color: foreground),
              ),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What the room looks at: the reveal or the year on top, the words in the
/// middle, the scores along the bottom.
///
/// The words are up for the whole round, from the first note on - the reason
/// to put the game on a wall. While the room guesses they carry no name, the
/// same as the sheet on the phone; the year card above names the song once it
/// is out. In a round played in this tab they follow the song.
///
/// The top slot keeps one height across the reveal, so the words do not jump
/// when the banner turns into the year.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.game,
    required this.spotify,
    required this.lyrics,
  });

  final GameController game;
  final SpotifySession spotify;
  final LyricsSource lyrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = game.currentSong;
    final revealed = game.phase == RoundPhase.revealed;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Everything grows with the height of the picture, which is what a
        // projector varies: 720p is still common, and a 1080p wall has twice
        // the room for words.
        final height = constraints.maxHeight;
        final top = (height * 0.24).clamp(120.0, 220.0);
        final tile = (height * 0.14).clamp(96.0, 132.0);
        final line = (height / 28).clamp(20.0, 36.0);

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (song == null)
                const Expanded(child: _StageIdle())
              else ...[
                SizedBox(
                  height: top,
                  child: revealed
                      ? _YearCard(game: game, wide: true)
                      : _RevealSlot(
                          onReveal: game.reveal,
                          inApp: _looksInApp(game, spotify),
                          service: game.service,
                          wide: true,
                        ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  // The words scroll themselves, so a scrollbar on the wall is
                  // only noise. The edges fade rather than cut a line in half.
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: [0, 0.06, 0.88, 1],
                      ).createShader(bounds),
                      child: LyricsView(
                        key: ValueKey(song.key),
                        song: song,
                        source: lyrics,
                        session: game.playingInApp ? spotify : null,
                        lineStyle: theme.textTheme.headlineSmall?.copyWith(
                          fontSize: line,
                          height: 1.25,
                        ),
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 72),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _SectionHeading(
                title: revealed ? 'Who got it right?' : 'Scores',
                targetScore: game.targetScore,
              ),
              if (revealed) ...[
                const SizedBox(height: 4),
                Text(
                  'Tap to give a point, long press to take one away.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _ScoreStrip(
                game: game,
                height: tile,
                onTap: revealed ? (player) => _givePoint(game, player) : null,
                onLongPress: revealed
                    ? (player) => _takePoint(game, player)
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The stage between two rounds, pointing at the pile of cards.
class _StageIdle extends StatelessWidget {
  const _StageIdle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _FitBody(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Icon(
            Icons.style_outlined,
            size: 96,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            'Draw a card',
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'and hold its QR code up to the camera',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The scores in one row along the bottom of the stage. Up to eight tiles fit
/// a 720p picture side by side; with only a few they keep a tile's width
/// rather than stretching across the wall.
class _ScoreStrip extends StatelessWidget {
  const _ScoreStrip({
    required this.game,
    required this.height,
    this.onTap,
    this.onLongPress,
  });

  final GameController game;
  final double height;
  final void Function(GamePlayer player)? onTap;
  final void Function(GamePlayer player)? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    final longPress = onLongPress;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        final count = game.players.length;
        final width = min(
          280.0,
          (constraints.maxWidth - gap * (count - 1)) / count,
        );

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final (index, player) in game.players.indexed) ...[
              if (index > 0) const SizedBox(width: gap),
              SizedBox(
                width: width,
                height: height,
                child: _PlayerTile(
                  player: player,
                  targetScore: game.targetScore,
                  onTap: tap == null ? null : () => tap(player),
                  onLongPress: longPress == null
                      ? null
                      : () => longPress(player),
                  large: true,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _FinishedBody extends StatelessWidget {
  const _FinishedBody({
    required this.game,
    required this.onUndo,
    required this.onRematch,
    required this.onHome,
  });

  final GameController game;
  final VoidCallback onUndo;
  final VoidCallback onRematch;
  final Future<void> Function() onHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winners = game.winners;
    final title = winners.length == 1
        ? '${winners.first.name} wins'
        : '${winners.map((p) => p.name).join(' and ')} win';

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // An icon, not the emoji: that one needs a font Flutter web fetches
          // at runtime, and on a slow line it shows up as an empty box.
          Icon(Icons.emoji_events, size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 32),
          Expanded(
            child: ListView(
              children: [
                for (final (index, player) in game.ranking.indexed)
                  ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(player.name),
                    trailing: Text(
                      '${player.score}',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
              ],
            ),
          ),
          // The last point was a slip of the finger more than once: the way
          // back to the reveal, where it can be taken away again.
          if (game.canUndoFinish) ...[
            TextButton.icon(
              onPressed: onUndo,
              icon: const Icon(Icons.undo),
              label: const Text('Back to the last round'),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: onRematch,
            child: const Text('Play again, same players'),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onHome, child: const Text('Back to start')),
        ],
      ),
    );
  }
}
