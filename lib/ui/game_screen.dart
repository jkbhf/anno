import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../data/game_store.dart';
import '../game/game_controller.dart';
import '../models/player.dart';
import '../models/song.dart';
import '../models/song_category.dart';
import '../music/in_app_launcher.dart';
import '../music/spotify_session.dart';
import 'app_scope.dart';
import 'centered_body.dart';
import 'haptics/haptics.dart';
import 'scanner_screen.dart';
import 'theme.dart';
import 'year_database_screen.dart';

/// Starts a game and cleans the controller up afterwards.
Future<void> openGame(
  BuildContext context, {
  required List<SongCategory> categories,
  required List<GamePlayer> players,
  required int targetScore,
}) async {
  final scope = AppScope.of(context);
  final controller = GameController(
    players: players,
    categories: categories,
    years: scope.years,
    targetScore: targetScore,
    persist: GameStore.save,
    launcher: InAppSpotifyLauncher(scope.spotify),
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

/// The main screen: scan, listen, reveal, hand out points.
class GameScreen extends StatefulWidget {
  const GameScreen({required this.controller, super.key});

  final GameController controller;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastPhase = _game.phase;
    _game.addListener(_onPhaseChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _spotify = AppScope.of(context).spotify;
  }

  @override
  void dispose() {
    unawaited(_spotify?.stop());
    _game.removeListener(_onPhaseChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
    if (state == AppLifecycleState.resumed) _game.onAppResumed();
  }

  /// Pushes the camera and returns the scanned code, or null when it was
  /// cancelled.
  Future<String?> _scanCode() async {
    if (_busy) return null;
    // Still inside the tap: a mobile browser grants sound from here, not from
    // the countdown three seconds later.
    unawaited(_spotify?.prepare() ?? Future<void>.value());
    _busy = true;
    try {
      return await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(builder: (_) => const ScannerScreen()),
      );
    } finally {
      _busy = false;
    }
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
        final year = _game.currentYear;
        _game.cancelRound();
        await _showNote(
          'No song for $year',
          _game.categories.length == 1
              ? '${_game.categories.single.name} has no entry for that year '
                    'yet. Draw another card or fill in the catalog.'
              : 'None of the chosen categories has an entry for that year '
                    'yet. Draw another card or fill in the catalog.',
        );
        return;
      case ScanOutcome.started:
        // Straight into the round. The screen that follows gives nothing away
        // - it is the scoreboard with a reveal button where the song card will
        // be - so there is nothing left for a countdown to cover.
        await _game.startPlayback();
    }
  }

  /// Ends the round and goes straight back to the camera - the scan is the
  /// only thing that happens next anyway.
  ///
  /// The round is only cleared once the camera closes again. Ending it first
  /// would drop the screen back to the big scan button for the length of the
  /// route animation, and that flash is exactly what this avoids.
  Future<void> _nextRound() async {
    if (_busy) return;

    if (_game.winners.isNotEmpty) {
      _game.nextRound();
      return;
    }

    final code = await _scanCode();
    if (!mounted) return;
    _game.nextRound();
    if (code == null) return;
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
        if (!context.mounted) return;
        Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _game,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
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
          body: SafeArea(child: CenteredBody(child: _body(context))),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    switch (_game.phase) {
      case RoundPhase.idle:
        return _IdleBody(game: _game, onScan: _startRound);
      case RoundPhase.countdown:
        // A single frame at most: the song is picked and playback is already
        // starting. Drawing anything here would only flicker.
        return const SizedBox.shrink();
      case RoundPhase.playing:
        return _PlayingBody(game: _game, spotify: AppScope.of(context).spotify);
      case RoundPhase.revealed:
        return _RevealBody(game: _game, onNextRound: _nextRound);
      case RoundPhase.finished:
        return _FinishedBody(
          game: _game,
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
  const _FitBody({required this.child, this.center = true});

  final Widget child;

  /// Centring suits a screen with one thing on it. The round has a stack of
  /// blocks that read top down, so it starts at the top and lets any space
  /// left over fall below the last button.
  final bool center;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.fromLTRB(20, 24, 20, 28);
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
  const _PlayingBody({required this.game, required this.spotify});

  final GameController game;
  final SpotifySession spotify;

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

    // Playing in the app is the good case: nobody leaves the game, so there is
    // nothing to come back from and the year waits for the button.
    final inApp = spotify.isReady;

    return _FitBody(
      center: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RevealSlot(onReveal: game.reveal, inApp: inApp),
          const SizedBox(height: 20),
          if (inApp)
            Center(
              child: TextButton.icon(
                onPressed: spotify.togglePause,
                icon: Icon(spotify.isPlaying ? Icons.pause : Icons.play_arrow),
                label: Text(spotify.isPlaying ? 'Pause' : 'Play on'),
              ),
            )
          // On the web a blocked popup looks exactly like a successful one, so
          // the way to Spotify stays reachable by hand.
          else if (kIsWeb)
            Center(
              child: TextButton.icon(
                onPressed: game.reopenInSpotify,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in Spotify'),
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
          const SizedBox(height: 36),
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
  const _RevealSlot({required this.onReveal, required this.inApp});

  final VoidCallback onReveal;
  final bool inApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: theme.colorScheme.outlineVariant, width: 2),
    );

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onReveal,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_note,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                inApp
                    ? 'The song is playing'
                    : 'The song is playing in Spotify',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                inApp
                    ? 'Everyone guesses the year.'
                    : 'Everyone guesses the year. Coming back to the app '
                          'reveals it too.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 20,
                      color: theme.colorScheme.onPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Reveal the year',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
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

class _RevealBody extends StatelessWidget {
  const _RevealBody({required this.game, required this.onNextRound});

  final GameController game;
  final VoidCallback onNextRound;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = game.currentSong;
    final year = game.currentYear ?? song?.year ?? 0;
    final accent = decadeColor(year);

    return _FitBody(
      center: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 34),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accent, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_originLine(game, song) case final origin?) ...[
                  Text(
                    origin,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: accent,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                // Scales down rather than wrapping: a broken year is the one
                // thing on this screen that must stay readable.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$year',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 84,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      letterSpacing: -2,
                      color: accent,
                    ),
                  ),
                ),
                if (song != null) ...[
                  const SizedBox(height: 18),
                  Text(
                    song.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 40),
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
            onTap: (player) {
              Haptics.point();
              game.addPoint(player);
            },
            onLongPress: (player) {
              Haptics.undo();
              game.removePoint(player);
            },
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

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.6,
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
  });

  final GamePlayer player;
  final int targetScore;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

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

    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            player.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          AnimatedScale(
            scale: _flashing ? 1.15 : 1,
            duration: const Duration(milliseconds: 120),
            child: Text(
              '${player.score}',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );

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

class _FinishedBody extends StatelessWidget {
  const _FinishedBody({
    required this.game,
    required this.onRematch,
    required this.onHome,
  });

  final GameController game;
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
          Text('🏆', style: theme.textTheme.displayLarge),
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
