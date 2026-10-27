import 'dart:async';

import 'package:flutter/material.dart';

import '../data/column_width_store.dart';
import '../data/lyrics_scale_store.dart';
import '../data/lyrics_sync_store.dart';
import '../data/slot_height_store.dart';
import '../data/tv_room_store.dart';
import '../game/game_controller.dart';
import '../music/lyrics.dart';
import '../sync/mirror_game.dart';
import '../sync/sync_messages.dart';
import '../sync/tv_link.dart';
import 'app_scope.dart';
import 'centered_body.dart';
import 'fullscreen/fullscreen.dart';
import 'game_screen.dart';
import 'wake_lock/wake_lock.dart';

/// The television: the landscape layout with the camera taken out of it, fed
/// from the phone that is running the game.
///
/// It decides nothing. Every button it draws is the phone's - the reveal, the
/// swap, the four moves of the song - and they are on the screen because the
/// room reads what is about to happen, not because anybody here can press
/// them. The only thing this screen owns is how the words look in this room:
/// their size and how far they run ahead of the song, both stepped from the
/// phone and kept here, because they are statements about this screen and the
/// distance to the sofa.
class TvScreen extends StatefulWidget {
  const TvScreen({this.link, super.key});

  /// For tests. Otherwise the app's own, from [AppScope].
  final TvLink? link;

  @override
  State<TvScreen> createState() => _TvScreenState();
}

class _TvScreenState extends State<TvScreen> {
  TvLink? _link;
  MirrorGame? _game;
  final MirrorSession _session = MirrorSession();

  double _lyricsScale = LyricsScaleStore.normal;
  double _columnShare = ColumnWidthStore.normal;
  double _slotShare = SlotHeightStore.normal;
  int _lyricsSync = LyricsSyncStore.none;
  bool _showScores = true;
  bool? _hasLyrics;

  /// The number over the words for a moment after a step, see [SyncFlash].
  int? _flash;
  Timer? _flashOff;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
    // A television that sleeps mid-round is the one failure this screen can
    // have all by itself.
    unawaited(WakeLock.hold());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final link = widget.link ?? AppScope.of(context).link;
    if (_link == link) return;
    _link = link;
    _game ??= MirrorGame.empty(AppScope.of(context).years);
    link.onMessage = _incoming;
    unawaited(_open(link));
  }

  /// Back to the room it had, where there was one: a reload must not hand the
  /// room a new code while the phone is still holding the old one.
  Future<void> _open(TvLink link) async {
    if (link.state == LinkState.paired && link.role == LinkRole.screen) return;
    await link.host(code: await TvRoomStore.load());
    final code = link.code;
    if (code != null) await TvRoomStore.save(code);
  }

  Future<void> _loadSettings() async {
    final scale = await LyricsScaleStore.load();
    final share = await ColumnWidthStore.load();
    final slot = await SlotHeightStore.load();
    final sync = await LyricsSyncStore.load();
    if (!mounted) return;
    setState(() {
      _lyricsScale = scale;
      _columnShare = share;
      _slotShare = slot;
      _lyricsSync = sync;
    });
  }

  void _incoming(SyncMessage message) {
    switch (message) {
      case GameSnapshot():
        _game?.apply(message);
        _session.readyIs(message.sessionReady);
        setState(() {
          _showScores = message.showScores;
          _hasLyrics = message.hasLyrics;
        });
      case PlaybackTick():
        _session.apply(message);
      case RemoteCommand():
        _step(message.step);
    }
  }

  void _step(RemoteStep step) {
    switch (step) {
      case RemoteStep.wordsBigger:
      case RemoteStep.wordsSmaller:
        final next = LyricsScaleStore.stepped(
          _lyricsScale,
          bigger: step == RemoteStep.wordsBigger,
        );
        if (next == _lyricsScale) return;
        setState(() => _lyricsScale = next);
        unawaited(LyricsScaleStore.save(next));
      case RemoteStep.wordsEarlier:
      case RemoteStep.wordsLater:
        final next = LyricsSyncStore.clamp(
          _lyricsSync +
              (step == RemoteStep.wordsEarlier
                  ? LyricsSyncStore.step
                  : -LyricsSyncStore.step),
        );
        // Said even where the press changed nothing: at the end of the range
        // silence reads as a key that is not bound.
        _sayIt(next);
        if (next == _lyricsSync) return;
        setState(() => _lyricsSync = next);
        unawaited(LyricsSyncStore.save(next));
    }
  }

  /// The number over the words, where whoever pressed is looking.
  void _sayIt(int ms) {
    setState(() => _flash = ms);
    _flashOff?.cancel();
    _flashOff = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _setColumnShare(double share) {
    final next = ColumnWidthStore.clamp(share);
    if (next == _columnShare) return;
    setState(() => _columnShare = next);
    unawaited(ColumnWidthStore.save(next));
  }

  void _setSlotShare(double share) {
    final next = SlotHeightStore.clamp(share);
    if (next == _slotShare) return;
    setState(() => _slotShare = next);
    unawaited(SlotHeightStore.save(next));
  }

  void _setLyricsScale(double scale) {
    final next = scale.clamp(LyricsScaleStore.min, LyricsScaleStore.max);
    if (next == _lyricsScale) return;
    setState(() => _lyricsScale = next);
    unawaited(LyricsScaleStore.save(next));
  }

  @override
  void dispose() {
    _flashOff?.cancel();
    final link = _link;
    if (link != null && link.onMessage == _incoming) link.onMessage = null;
    unawaited(link?.leave() ?? Future<void>.value());
    unawaited(WakeLock.release());
    _session.dispose();
    _game?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final link = _link;
    if (game == null || link == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([game, link]),
          builder: (context, _) {
            if (!game.hasRound || !link.isPaired) {
              return CenteredBody(child: _Pairing(link: link));
            }
            if (game.phase == RoundPhase.finished) {
              return CenteredBody(child: FinishedBody(game: game));
            }
            // The three seconds the phone spends counting down. The round is
            // drawn but not started, so the layout would say "Scan a card"
            // again for a moment - a screen flashing back to the state before
            // the card reads as a card that did not take.
            if (game.phase == RoundPhase.countdown) {
              return const CenteredBody(child: _Starting());
            }
            return Stack(
              children: [
                Positioned.fill(child: _round(game)),
                if (_flash case final ms?)
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(child: SyncFlash(offsetMs: ms)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _round(MirrorGame game) {
    return WideRound(
      game: game,
      spotify: _session,
      lyrics: sharedLyrics,
      // The lens is on the phone. Everything else about the column stays.
      camera: null,
      cameraless: true,
      onCode: (_) {},
      onCloseCamera: () {},
      onScan: () {},
      onNextRound: () {},
      onRedraw: () {},
      onUndoRedraw: () {},
      lyricsScale: _lyricsScale,
      onLyricsScale: _setLyricsScale,
      lyricsSync: _lyricsSync,
      // The arrows are on the phone, where the thumb is. What belongs here is
      // the answer, and that is the flash over the words.
      syncMode: false,
      onSync: (_) {},
      hasLyrics: _hasLyrics,
      showScores: _showScores,
      // A key nobody in the room can press, written on the wall.
      shortcuts: false,
      columnShare: _columnShare,
      onColumnShare: _setColumnShare,
      slotShare: _slotShare,
      onSlotShare: _setSlotShare,
    );
  }
}

/// The card has been read and the song is on its way.
///
/// The phone counts down behind this, out loud and in the hand of whoever
/// scanned; the room only needs to know that something is coming.
class _Starting extends StatelessWidget {
  const _Starting();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'Here it comes',
        style: theme.textTheme.headlineMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The code, while there is nothing else to show.
///
/// Six characters big enough to read from the sofa, and the one sentence that
/// says what to do with them. Nothing is scanned here: the phone has a
/// keyboard, and six characters typed beat a camera pointed at a television.
class _Pairing extends StatelessWidget {
  const _Pairing({required this.link});

  final TvLink link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = link.code;

    final (String title, String body) = switch (link.state) {
      LinkState.off => ('Not connected', 'Nothing is being tried.'),
      LinkState.connecting => (
        'Connecting',
        'One moment - looking for the relay.',
      ),
      LinkState.failed => (
        'That did not work',
        link.problem ?? 'Unknown reason.',
      ),
      LinkState.waiting || LinkState.paired => (
        'Anno on this screen',
        'Open the game on your phone, choose "Play on a television" and '
            'type this code in.',
      ),
    };

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.tv, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 20),
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (code != null && link.state != LinkState.failed) ...[
            const SizedBox(height: 32),
            FittedBox(
              child: Text(
                // Spaced out, because six characters read off a television
                // across a room are read one at a time.
                code.split('').join(' '),
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
          if (link.isPaired) ...[
            const SizedBox(height: 24),
            Text(
              'Paired. Waiting for the first card.',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          if (Fullscreen.isSupported) ...[
            const SizedBox(height: 32),
            // Here and nowhere else on this screen: a browser grants
            // fullscreen to a gesture, and this is the one moment somebody is
            // standing in front of the television with a remote in hand.
            OutlinedButton.icon(
              onPressed: Fullscreen.toggle,
              icon: const Icon(Icons.fullscreen),
              label: const Text('Fullscreen'),
            ),
          ],
        ],
      ),
    );
  }
}
