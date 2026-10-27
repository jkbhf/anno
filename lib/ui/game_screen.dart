import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/column_width_store.dart';
import '../data/game_store.dart';
import '../data/lyrics_scale_store.dart';
import '../data/lyrics_sync_store.dart';
import '../data/played_songs_store.dart';
import '../data/show_scores_store.dart';
import '../data/skipped_songs_store.dart';
import '../data/slot_height_store.dart';
import '../data/year_database.dart';
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
import 'fullscreen/fullscreen.dart';
import 'haptics/haptics.dart';
import 'layout.dart';
import 'lyrics_sheet.dart';
import 'pinch_scale.dart';
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
  int? fromYear,
  int? toYear,
  List<int> playedYears = const [],
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
    // Set only for a game without cards, where the years are drawn instead
    // of scanned.
    fromYear: fromYear,
    toYear: toYear,
    playedYears: playedYears,
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

/// What the keys do, in one place: the hint line in the column reads the same
/// list the shortcuts are built from, so the two cannot drift apart.
///
/// Two keys for every move of the song - an arrow and its WASD letter - which
/// cost nothing beside each other and let a hand stay where it is. The pair is
/// laid out the way the moves are: the horizontal keys step ten seconds and
/// the vertical ones jump. The single keys are what a round is made of:
/// playing, revealing, and the swap with its undo.
///
/// Taking these keys means the game screen keeps them from Flutter: inside it,
/// space and enter no longer press the button that happens to have the focus
/// and the arrows no longer walk from one to the next. For a game run with a
/// mouse on a laptop that is the right trade, and it is the whole reason the
/// list is short.
enum GameShortcut {
  playPause([LogicalKeyboardKey.space], 'Space', 'Play / pause'),
  back10(
    [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA],
    '← A',
    '−10s',
  ),
  forward10(
    [LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD],
    '→ D',
    '+10s',
  ),
  middle(
    [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW],
    '↑ W',
    'Middle',
  ),
  start(
    [LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS],
    '↓ S',
    'From the start',
  ),
  reveal([LogicalKeyboardKey.enter], 'Enter', 'Reveal the year'),
  redraw([LogicalKeyboardKey.keyN], 'N', 'Nobody knows it'),
  undoRedraw([LogicalKeyboardKey.keyZ], 'Z', 'Take the swap back'),
  // The words against the song, from the keyboard - the same number the sync
  // mode sets with its arrows, for whoever is running the game from a laptop
  // while it plays. Control, because the bare keys are the song's.
  wordsEarlier(
    [
      LogicalKeyboardKey.add,
      LogicalKeyboardKey.numpadAdd,
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.keyD,
    ],
    'Ctrl +/D',
    'Words earlier',
    control: true,
  ),
  wordsLater(
    [
      LogicalKeyboardKey.minus,
      LogicalKeyboardKey.numpadSubtract,
      LogicalKeyboardKey.keyA,
    ],
    'Ctrl −/A',
    'Words later',
    control: true,
  );

  const GameShortcut(this.keys, this.label, this.does, {this.control = false});

  final List<LogicalKeyboardKey> keys;

  /// Whether control has to be held. The bare keys are taken by the song, and
  /// these are a setting rather than a move - so they ask for the modifier
  /// every editor asks for to resize something.
  final bool control;

  /// How the keys are written in the hint line.
  final String label;

  /// What it does, in the hint line.
  final String does;

  /// Whether it would do anything right now - the one rule both the bindings
  /// and the hint line read, so a key is written down exactly when it works.
  ///
  /// A key does only what a finger could: the song can only be moved in a
  /// round that plays in this tab, a year can only be revealed while one is
  /// running, and the swap and its undo are the controller's own two questions.
  bool isLive(GameController game) => switch (this) {
    playPause || back10 || forward10 || middle || start => game.playingInApp,
    reveal => game.phase == RoundPhase.playing,
    redraw => game.canRedraw,
    undoRedraw => game.canUndoRedraw,
    // Whenever words are on a screen. The number is a setting of the room's
    // and not a move in the round, so it can be set in a link round too -
    // there it is simply not seen until a song plays in this tab.
    wordsEarlier || wordsLater => game.currentSong != null,
  };
}

/// The grip between the two halves of the wide layout, so a test can drag the
/// one thing on the screen that has no words on it.
@visibleForTesting
const Key splitHandleKey = Key('split-handle');

/// The reveal in the side column - the camera's slot while a round plays, see
/// [_CameraSlot]. Named so a test can press the panel rather than the words
/// on it.
@visibleForTesting
const Key revealInColumnKey = Key('reveal-in-column');

/// The grip under the reveal card, which sets how tall that box is. Named for
/// the same reason the split handle is: it has no words on it.
@visibleForTesting
const Key slotHandleKey = Key('slot-handle');

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

  /// How big the words are on the stage, see [LyricsScaleStore]. The saved one
  /// arrives a frame or two in, which is soon enough: the first round is still
  /// a card away.
  double _lyricsScale = LyricsScaleStore.normal;

  /// Whether the scoreboard is on the screen, see [ShowScoresStore].
  bool _showScores = true;

  /// How much of the screen the side column takes, see [ColumnWidthStore].
  double _columnShare = ColumnWidthStore.normal;

  /// How much of the column the reveal card takes, see [SlotHeightStore].
  double _slotShare = SlotHeightStore.normal;

  /// How far the words run ahead of the song, see [LyricsSyncStore].
  int _lyricsSync = LyricsSyncStore.none;

  /// Whether the panel for setting that number is in the column, see
  /// [_SyncPanel]. Switched on from the menu and off again the same way - it
  /// is a mode for the few minutes it takes to find the number, so it is not
  /// kept the way the number itself is.
  bool _syncMode = false;

  /// Says the number on the screen for a moment after it changed, so a press
  /// of the keys is answered where the eyes are - on the words, not in the
  /// corner the panel sits in. Null while nothing is being said.
  int? _syncFlash;
  Timer? _syncFlashOff;

  /// How long that stays up.
  static const Duration _flashFor = Duration(milliseconds: 1100);

  /// Whether the song of the round has words at all, and which song the
  /// answer belongs to. Null while nobody has answered yet.
  ///
  /// The stage says it where the words would be, and the column says it
  /// beside the controls - whoever runs the game is looking there, and on a
  /// projector the stage is across the room.
  bool? _hasLyrics;
  String? _lyricsFor;

  /// Whether the layout the last frame drew was the wide one. Read by the
  /// phase listener, which runs outside a build and must not go looking for a
  /// MediaQuery of its own.
  bool _wide = false;

  /// When the camera that opened itself came up, see [_onPhaseChanged]. Null
  /// while no such camera is open.
  ///
  /// The card of the round is only read past for [_staleCard] after that: it
  /// is the card lying in front of the lens at the moment of the reveal, and
  /// a second later it is a card somebody is holding up on purpose. The first
  /// try at this had no window and ignored that card for as long as the camera
  /// stayed open, which read as a camera that scanned nothing at all
  /// (2026-10-27) - the same card held up again is the normal way to try it.
  DateTime? _autoScanAt;

  /// How long the card of the round stays ignored after the camera opens by
  /// itself. Long enough for the one lying on the table, short enough that
  /// picking it up and presenting it counts.
  static const Duration _staleCard = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastPhase = _game.phase;
    _game.addListener(_onPhaseChanged);
    unawaited(WakeLock.hold());
    unawaited(_loadSettings());
    _trackLyrics();
    // The first card of a new game: the camera is what the game wants from
    // whoever opened it, so it comes up by itself rather than behind a tap on
    // a button whose only job is to open it - the box in the column on a wide
    // screen, the scanner page on a phone. Only at the very start: from the
    // second round on the reveal is what opens it, and a game resumed
    // mid-round has a song running.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _busy) return;
      // Without cards there is no camera to open, and a game that starts
      // playing the moment it is opened would startle a room that has not
      // sat down yet: there the first round waits for the tap that every
      // later one waits for too.
      if (_game.withoutCards) return;
      if (_game.phase != RoundPhase.idle || _game.lastScannedCode != null) {
        return;
      }
      unawaited(_startRound());
    });
  }

  Future<void> _loadSettings() async {
    final scale = await LyricsScaleStore.load();
    final scores = await ShowScoresStore.load();
    final share = await ColumnWidthStore.load();
    final slot = await SlotHeightStore.load();
    final sync = await LyricsSyncStore.load();
    if (!mounted) return;
    setState(() {
      _lyricsScale = scale;
      _showScores = scores;
      _columnShare = share;
      _slotShare = slot;
      _lyricsSync = sync;
    });
  }

  /// The divider was dragged. Saved on the way, not at the end of the drag:
  /// a write per frame is cheap next to one more thing to remember.
  void _setColumnShare(double share) {
    final next = ColumnWidthStore.clamp(share);
    if (next == _columnShare) return;
    setState(() => _columnShare = next);
    unawaited(ColumnWidthStore.save(next));
  }

  /// The reveal card was dragged taller or shorter.
  void _setSlotShare(double share) {
    final next = SlotHeightStore.clamp(share);
    if (next == _slotShare) return;
    setState(() => _slotShare = next);
    unawaited(SlotHeightStore.save(next));
  }

  /// Sets how far the words run ahead of the song, see [LyricsSyncStore].
  ///
  /// There is no dialog for this any more and no click to compare against: it
  /// is set while the song plays and the words run, which is the only thing
  /// that ever told anybody whether the number is right. A step says itself on
  /// the screen for a moment, so the keys can be pressed without looking away
  /// from the words.
  void _nudgeSync({required bool earlier}) {
    _setLyricsSync(
      _lyricsSync + (earlier ? LyricsSyncStore.step : -LyricsSyncStore.step),
    );
  }

  void _setLyricsSync(int ms) {
    final next = LyricsSyncStore.clamp(ms);
    if (next == _lyricsSync) {
      // Still say the number: at the end of the range a press that does
      // nothing otherwise looks like a key that is not bound.
      _flashSync(next);
      return;
    }
    setState(() => _lyricsSync = next);
    unawaited(LyricsSyncStore.save(next));
    _flashSync(next);
  }

  void _flashSync(int ms) {
    setState(() => _syncFlash = ms);
    _syncFlashOff?.cancel();
    _syncFlashOff = Timer(_flashFor, () {
      if (mounted) setState(() => _syncFlash = null);
    });
  }

  void _toggleSyncMode() => setState(() => _syncMode = !_syncMode);

  /// Asks whether the song of the round has words, for the line that says so
  /// where the controls are. The stage asks for itself, and both land on the
  /// same cached answer.
  void _trackLyrics() {
    final song = _game.currentSong;
    if (song == null) {
      if (_lyricsFor != null) {
        _lyricsFor = null;
        _hasLyrics = null;
      }
      return;
    }
    if (_lyricsFor == song.key) return;
    _lyricsFor = song.key;
    _hasLyrics = null;
    unawaited(
      (widget.lyrics ?? sharedLyrics).find(song).then(
        (lyrics) {
          if (!mounted || _lyricsFor != song.key) return;
          setState(
            () => _hasLyrics = lyrics != null && lyrics.lines.isNotEmpty,
          );
        },
        // A source that did not answer is not a song without words, and the
        // view beside this says so for itself.
        onError: (Object _) {},
      ),
    );
  }

  void _toggleScores() {
    setState(() => _showScores = !_showScores);
    unawaited(ShowScoresStore.save(shown: _showScores));
  }

  /// A press of smaller or bigger in the menu. It is the same room and the
  /// same wall next time, so the size is kept.
  void _stepLyricsScale({required bool bigger}) =>
      _setLyricsScale(LyricsScaleStore.stepped(_lyricsScale, bigger: bigger));

  /// What two fingers on the words asked for, see [PinchScale]. Saved on the
  /// way like the column's width: a write per frame is cheap next to one more
  /// thing to remember.
  void _setLyricsScale(double scale) {
    final next = scale.clamp(LyricsScaleStore.min, LyricsScaleStore.max);
    if (next == _lyricsScale) return;
    setState(() => _lyricsScale = next);
    unawaited(LyricsScaleStore.save(next));
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
    _syncFlashOff?.cancel();
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
    // A swap and the next round both bring another song, and with it another
    // answer to whether it has words.
    _trackLyrics();
    if (phase == RoundPhase.revealed && _lastPhase != RoundPhase.revealed) {
      Haptics.reveal();
      // The round is over, so the next card is the only thing left to do: the
      // camera comes up by itself in the slot the reveal was just pressed in,
      // and the year goes to the stage. Still inside the tap that revealed,
      // which is what lets a mobile browser unlock sound for the next round.
      // Without cards there is nothing to hold up to a lens, and drawing the
      // next year here would start its song over the points still being
      // handed out. There the next round is the tap it says it is.
      if (_wide && _inlineScan == null && !_game.withoutCards) {
        _autoScanAt = DateTime.now();
        unawaited(_nextRound());
      }
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
        syncMs: _lyricsSync,
        hideSong: !_game.isRevealed,
      ),
    );
  }

  /// Asks for the words while the countdown runs, so the sheet has them when
  /// somebody taps - and so the line about a song without any is right by the
  /// time the round is on screen. A failure here is no matter: the sheet asks
  /// again.
  void _prefetchLyrics() => _trackLyrics();

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
  /// Whether a code the camera read is the card of the round on screen. The
  /// camera that opened itself is pointing straight at it, and a round nobody
  /// asked for would land on top of the reveal.
  ///
  /// Handed to [ScannerView.ignore], which reads past it and keeps looking -
  /// dropping it after the view reported it would lock the camera.
  bool _ignoreCode(String code) {
    final opened = _autoScanAt;
    final inPlay = _game.lastScannedCode;
    if (opened == null || inPlay == null) return false;
    if (DateTime.now().difference(opened) > _staleCard) return false;
    return YearDatabase.normalizeKey(code) == YearDatabase.normalizeKey(inPlay);
  }

  /// A code the inline camera read. The real camera has filtered it already;
  /// this is the same test again for a stand-in that does not know about
  /// [ScannerView.ignore], and it is cheap.
  void _onInlineCode(String code) {
    if (_ignoreCode(code)) return;
    _closeInlineScan(code);
  }

  void _closeInlineScan([String? code]) {
    final scan = _inlineScan;
    if (scan == null) return;
    _autoScanAt = null;
    setState(() => _inlineScan = null);
    scan.complete(code);
  }

  Future<void> _startRound() async {
    if (_game.withoutCards) return _drawYear();
    final code = await _scanCode();
    if (!mounted || code == null) return;
    await _handleCode(code);
  }

  /// The round of a game without cards: the device draws the year.
  ///
  /// It goes through [_handleCode] like a scan does - the year is handed over
  /// as the code it would have been on a card - so the countdown, the launch
  /// and everything after it have one path and not two.
  Future<void> _drawYear() async {
    if (_busy) return;
    // Still inside the tap, the same as a scan: a mobile browser grants sound
    // from here and not from the countdown three seconds later.
    if (_game.service == MusicService.spotify) {
      unawaited(_spotify?.prepare() ?? Future<void>.value());
    }
    final next = _game.nextYear();
    if (next == null) {
      await _showNote(
        'No year to play',
        'None of the chosen decks has a song in that range. Change the '
            'range or the decks.',
      );
      return;
    }
    if (next.startedOver && mounted) {
      final (from, to) = (_game.fromYear, _game.toYear);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Every year from $from to $to has been played - starting over.',
          ),
        ),
      );
    }
    _busy = true;
    try {
      await _handleCode('${next.year}');
    } finally {
      _busy = false;
    }
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

    // Without cards there is nothing to wait for: the tap that asks for the
    // next round is also the one that draws its year.
    if (_game.withoutCards) {
      _game.nextRound();
      await _drawYear();
      return;
    }

    final code = await _scanCode();
    if (!mounted || code == null) return;
    // The camera opens at the reveal and waits there while the points are
    // handed out, so the game can be won after it opened. The card then goes
    // unused: what comes next is the finish, not another round.
    if (_game.winners.isNotEmpty) {
      _game.nextRound();
      return;
    }
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
        final playedYears = _game.playedYears.toList();
        final (from, to) = (_game.fromYear, _game.toYear);
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
                initialFromYear: from,
                initialToYear: to,
                playedYears: playedYears,
              ),
            ),
          ),
        );
      case 'scores':
        _toggleScores();
      case 'words.bigger':
        _stepLyricsScale(bigger: true);
      case 'words.smaller':
        _stepLyricsScale(bigger: false);
      case 'words.sync':
        _toggleSyncMode();
      case 'fullscreen':
        // A gesture is what the browser grants it to, and this is one.
        await Fullscreen.toggle();
      case 'leave':
        await _onBack(false);
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

  /// Runs a shortcut, or nothing where it would do nothing anyway - see
  /// [GameShortcut.isLive], the same rule the hint line reads.
  void _runShortcut(GameShortcut shortcut) {
    if (!shortcut.isLive(_game)) return;
    final spotify = _spotify;
    switch (shortcut) {
      case GameShortcut.reveal:
        _game.reveal();
      case GameShortcut.redraw:
        unawaited(_redraw());
      case GameShortcut.undoRedraw:
        unawaited(_undoRedraw());
      case GameShortcut.playPause:
        unawaited(spotify?.togglePause());
      case GameShortcut.back10:
        if (spotify != null) seekSongBy(spotify, -SongProgressBar.skip);
      case GameShortcut.forward10:
        if (spotify != null) seekSongBy(spotify, SongProgressBar.skip);
      case GameShortcut.middle:
        if (spotify != null) unawaited(spotify.seek(spotify.duration ~/ 2));
      case GameShortcut.start:
        if (spotify != null) unawaited(spotify.seek(Duration.zero));
      case GameShortcut.wordsEarlier:
        _nudgeSync(earlier: true);
      case GameShortcut.wordsLater:
        _nudgeSync(earlier: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Below the app's own shortcuts and above every button on the screen, so
    // these keys are taken before anything else can have them. A dialog or the
    // countdown is a route of its own and keeps its keys.
    return CallbackShortcuts(
      bindings: {
        for (final shortcut in GameShortcut.values)
          for (final key in shortcut.keys)
            SingleActivator(key, control: shortcut.control): () =>
                _runShortcut(shortcut),
      },
      child: Focus(
        autofocus: true,
        child: PopScope<void>(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) => _onBack(didPop),
          child: _scaffold(context),
        ),
      ),
    );
  }

  Widget _scaffold(BuildContext context) {
    final wide = isWideScreen(MediaQuery.sizeOf(context));
    _wide = wide;
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
        final round = wide && _game.phase != RoundPhase.finished
            ? _wideBody(context)
            : CenteredBody(child: _body(context));
        // The number says itself over whatever is on the screen, so a press
        // of the keys is answered where the words are.
        final body = Stack(
          children: [
            Positioned.fill(child: round),
            if (_syncFlash case final ms?)
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(child: _SyncFlash(offsetMs: ms)),
              ),
          ],
        );
        return Scaffold(
          // The wide layout has no bar: 56 pixels of a landscape phone's 412
          // for a deck name the room does not need and a menu that belongs to
          // whoever runs the game anyway. It moved into the side column, the
          // way out of the game with it - the bar's back arrow went too.
          appBar: wide
              ? null
              : AppBar(
                  title: Text(
                    _game.categories.length == 1
                        ? _game.categories.single.name
                        : '${_game.categories.length} categories',
                  ),
                  actions: [_menu(wide: false)],
                ),
          body: SafeArea(child: body),
        );
      },
    );
  }

  /// The menu, in the bar on a phone and in the side column on a wide screen.
  ///
  /// Only the wide one carries the way out: there the bar that held the back
  /// arrow is gone, and a game nobody can leave is worse than a long menu.
  Widget _menu({required bool wide}) {
    return PopupMenuButton<String>(
      tooltip: 'Menu',
      onSelected: _onMenu,
      itemBuilder: (context) => [
        // Read as the menu opens, like the fullscreen entry below.
        PopupMenuItem(
          value: 'scores',
          child: Text(_showScores ? 'Hide the scores' : 'Show the scores'),
        ),
        // The size of the words on the stage. A press closes the menu, which
        // is the cost of having it in here rather than as a row in the column
        // - it is set once for the room and then left alone, so a second trip
        // through the menu for a second step is a fair price for the space.
        // Two fingers on the words do the same thing without the trip, which
        // is why the percentage is not written down here any more.
        PopupMenuItem(
          value: 'words.bigger',
          enabled: _lyricsScale < LyricsScaleStore.max,
          child: const Text('Bigger words'),
        ),
        PopupMenuItem(
          value: 'words.smaller',
          enabled: _lyricsScale > LyricsScaleStore.min,
          child: const Text('Smaller words'),
        ),
        // The mode, not a dialog: the number is found against the running
        // song, so what it needs is a pair of arrows beside the words rather
        // than a window over them.
        PopupMenuItem(
          value: 'words.sync',
          child: Text(_syncMode ? 'Done syncing the words' : 'Sync the words'),
        ),
        const PopupMenuItem(value: 'reset', child: Text('Reset scores')),
        const PopupMenuItem(value: 'category', child: Text('Change category')),
        const PopupMenuItem(value: 'years', child: Text('Year database')),
        // Read as the menu opens, so the entry says what the tap will do.
        if (Fullscreen.isSupported)
          PopupMenuItem(
            value: 'fullscreen',
            child: Text(Fullscreen.isOn ? 'Leave fullscreen' : 'Fullscreen'),
          ),
        const PopupMenuItem(value: 'new', child: Text('New game')),
        if (wide)
          const PopupMenuItem(value: 'leave', child: Text('Leave the game')),
      ],
    );
  }

  /// The round on a wide screen, see [_WideRound].
  Widget _wideBody(BuildContext context) {
    // As on the phone: the countdown is up over the screen, or the song is
    // starting within the frame.
    if (_game.phase == RoundPhase.countdown) return const SizedBox.shrink();
    // The menu in the corner of the screen rather than in one of the two
    // halves: it belongs to neither, it is reached once or twice an evening,
    // and the corner is the one place no round ever needs.
    return Stack(
      children: [
        Positioned.fill(child: _wideRound(context)),
        Positioned(top: 8, right: 12, child: _menu(wide: true)),
      ],
    );
  }

  Widget _wideRound(BuildContext context) {
    return _WideRound(
      game: _game,
      spotify: AppScope.of(context).spotify,
      lyrics: widget.lyrics ?? sharedLyrics,
      camera: _inlineScan == null
          ? null
          : widget.camera ??
                (context, onCode) =>
                    ScannerView(onCode: onCode, ignore: _ignoreCode),
      onCode: _onInlineCode,
      onCloseCamera: _closeInlineScan,
      onScan: _startRound,
      onNextRound: _nextRound,
      onRedraw: _redraw,
      onUndoRedraw: _undoRedraw,
      lyricsScale: _lyricsScale,
      onLyricsScale: _setLyricsScale,
      lyricsSync: _lyricsSync,
      syncMode: _syncMode,
      onSync: _setLyricsSync,
      hasLyrics: _hasLyrics,
      showScores: _showScores,
      shortcuts: hasKeyboard,
      columnShare: _columnShare,
      onColumnShare: _setColumnShare,
      slotShare: _slotShare,
      onSlotShare: _setSlotShare,
    );
  }

  /// The arrows for the sync, where the mode is on. Null otherwise - on the
  /// phone there is no column to put them in, so they go into the round's own
  /// stack of blocks and come out of it again when the mode ends.
  Widget? _syncPanel() => _syncMode
      ? _SyncPanel(offsetMs: _lyricsSync, onSync: _setLyricsSync)
      : null;

  Widget _body(BuildContext context) {
    switch (_game.phase) {
      case RoundPhase.idle:
        return _IdleBody(
          game: _game,
          onScan: _startRound,
          showScores: _showScores,
        );
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
          hasLyrics: _hasLyrics,
          showScores: _showScores,
          sync: _syncPanel(),
        );
      case RoundPhase.revealed:
        return _RevealBody(
          game: _game,
          onNextRound: _nextRound,
          onLyrics: _showLyrics,
          hasLyrics: _hasLyrics,
          showScores: _showScores,
          sync: _syncPanel(),
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
  const _IdleBody({
    required this.game,
    required this.onScan,
    required this.showScores,
  });

  final GameController game;
  final VoidCallback onScan;
  final bool showScores;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Without cards the same circle draws the year instead of opening the
    // camera: one thing to tap, whichever way the game is being played.
    final cardless = game.withoutCards;

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
                  cardless ? Icons.casino_outlined : Icons.qr_code_scanner,
                  size: 96,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            cardless ? 'Draw a year' : 'Scan a card',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            cardless
                ? '${game.fromYear} to ${game.toYear}, '
                      '${game.playedYears.length} of '
                      '${game.playableYears.length} played'
                : 'QR code on the front of the card',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (showScores) ...[
            const SizedBox(height: 56),
            _SectionHeading(title: 'Scores', targetScore: game.targetScore),
            const SizedBox(height: 16),
            _PlayerGrid(game: game),
          ],
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
    required this.hasLyrics,
    required this.showScores,
    this.sync,
  });

  final GameController game;
  final SpotifySession spotify;
  final VoidCallback onRedraw;
  final VoidCallback onUndoRedraw;
  final VoidCallback onLyrics;

  /// Whether the song has words at all, null while nobody knows yet.
  final bool? hasLyrics;
  final bool showScores;

  /// The sync arrows while that mode is on.
  final Widget? sync;

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
          if (sync case final panel?) ...[panel, const SizedBox(height: 12)],
          _SongControls(
            game: game,
            spotify: spotify,
            onRedraw: onRedraw,
            onUndoRedraw: onUndoRedraw,
            onLyrics: onLyrics,
            hasLyrics: hasLyrics,
          ),
          if (showScores) ...[
            const SizedBox(height: 32),
            _SectionHeading(title: 'Scores', targetScore: game.targetScore),
            const SizedBox(height: 16),
            // The same tiles as the reveal, but inert: points are handed out
            // once the year is up, not while the group is still guessing.
            _PlayerGrid(game: game),
          ],
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
    this.hasLyrics,
    this.inColumn = false,
  });

  final GameController game;
  final SpotifySession spotify;
  final VoidCallback onRedraw;
  final VoidCallback onUndoRedraw;

  /// Null where the words are up anyway - the stage of the wide layout.
  final VoidCallback? onLyrics;

  /// Whether the song has words at all, null while nobody knows yet. Where
  /// there are none it is said here, beside the controls: whoever runs the
  /// game is looking at this half, and on a projector the stage is across the
  /// room.
  final bool? hasLyrics;

  /// In the side column of the wide layout. Two things follow from it: the
  /// swap gets its short label, because the column is 214 wide on a phone
  /// turned over and the sentence wraps to four lines there, and the player
  /// is not here at all - it is the band across the bottom of the screen.
  final bool inColumn;

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
    //
    // Only once the launch has answered, though: a swap hands the song over
    // again, and for those few frames `playingInApp` is false while the round
    // is on its way back into the tab. Shown on that, the button flashed up
    // after every press of "nobody knows it" and went again - see
    // [_looksInApp], which is the same rule the rest of the screen reads.
    final openButton = kIsWeb && !_looksInApp(game, spotify)
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
        // In the column the player is somewhere else entirely, so there is no
        // room to keep for it either - the band at the bottom of the screen
        // does that for itself. The way back to a swallowed popup stays,
        // which is what the button is for: an in-app round never lost one.
        if (inColumn) ...[
          if (!inApp) ?openButton,
        ] else if (inApp)
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
            child: _LyricsButton(onLyrics: lyrics, has: hasLyrics),
          )
        // In the column the words are on the stage, so there is no button to
        // turn into the message - it is said as a line of its own, and only
        // when there is something to say.
        else if (hasLyrics == false)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: _NoLyrics(),
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
        //
        // A button with a border and a height of its own, not a line of text
        // with a ripple: it is pressed in the middle of a round, often in the
        // dark, and as a text button it was both hard to hit and the one
        // thing on the panel that looked like it had been left there.
        if (game.canRedraw) ...[
          const SizedBox(height: 12),
          // The undo sits in the same row, so it comes and goes without
          // moving anything.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRedraw,
                  icon: const Icon(Icons.shuffle, size: 20),
                  label: Text(
                    inColumn
                        ? 'Nobody knows it'
                        : 'Nobody knows it — draw another',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: const StadiumBorder(),
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
              ),
              // Always there, greyed out until there is a swap to take back:
              // a button that comes and goes is one nobody learns the place
              // of, and the place is the point of it.
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: IconButton.outlined(
                  tooltip: 'Back to the last song',
                  onPressed: game.canUndoRedraw ? onUndoRedraw : null,
                  icon: const Icon(Icons.undo),
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(52),
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The way to the words on the phone - or, where the song has none, the line
/// that says so in the button's place.
///
/// Dead rather than gone: the button stands where it stands in every round,
/// and a round whose song has no text says that much instead of leaving a gap
/// whoever is holding the phone has to interpret.
class _LyricsButton extends StatelessWidget {
  const _LyricsButton({required this.onLyrics, required this.has});

  final VoidCallback onLyrics;

  /// Null while the source has not answered yet - then the button opens the
  /// sheet, which says for itself what came of the question.
  final bool? has;

  @override
  Widget build(BuildContext context) {
    if (has == false) return const _NoLyrics();

    return TextButton.icon(
      onPressed: onLyrics,
      icon: const Icon(Icons.lyrics_outlined),
      label: const Text('Lyrics'),
    );
  }
}

/// What a song without a text gets instead of the words.
class _NoLyrics extends StatelessWidget {
  const _NoLyrics();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lyrics_outlined, size: 18, color: muted),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'No lyrics for this song',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

/// The sync, set against the running song: two arrows and the number between
/// them.
///
/// This is what the dialog with its click and its flash used to be, and it is
/// in the column rather than over the screen for the reason the dialog could
/// never work around - the only honest test of the number is the words
/// against the music, so the song has to go on playing while it is being set.
/// A finger on the arrows is the same step the keys make.
class _SyncPanel extends StatelessWidget {
  const _SyncPanel({required this.offsetMs, required this.onSync});

  final int offsetMs;
  final ValueChanged<int> onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Sync the words',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: 'The words later',
                onPressed: offsetMs <= LyricsSyncStore.min
                    ? null
                    : () => onSync(offsetMs - LyricsSyncStore.step),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${offsetMs > 0 ? '+' : ''}$offsetMs ms',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'The words earlier',
                onPressed: offsetMs >= LyricsSyncStore.max
                    ? null
                    : () => onSync(offsetMs + LyricsSyncStore.step),
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The number, said over the screen for a moment after it changed.
///
/// A press of the keys happens while somebody is watching the words, which is
/// the whole point of setting it there - so the answer comes to the words
/// rather than making them look for a panel.
class _SyncFlash extends StatelessWidget {
  const _SyncFlash({required this.offsetMs});

  final int offsetMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.inverseSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          'Words ${offsetMs > 0 ? '+' : ''}$offsetMs ms',
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onInverseSurface,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
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
  const _RevealSlot({
    required this.onReveal,
    required this.inApp,
    required this.service,
  });

  final VoidCallback onReveal;
  final bool inApp;
  final MusicService service;

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
      textAlign: TextAlign.center,
      style: theme.textTheme.titleMedium,
    );
    final hint = Text(
      inApp
          ? 'Everyone guesses the year.'
          : 'Everyone guesses the year. Coming back to the app reveals it too.',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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

/// The answer on the phone: the year, tinted by its decade, with the song
/// under it. The wide layout keeps the words on its stage and shows the year
/// in the column instead, see [_ColumnYear].
class _YearCard extends StatelessWidget {
  const _YearCard({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = game.currentSong;
    final year = game.currentYear ?? song?.year ?? 0;
    final accent = decadeColor(year);

    final origin = switch (_originLine(game, song)) {
      final line? => Text(
        line,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelLarge?.copyWith(
          color: accent,
          letterSpacing: 0.4,
        ),
      ),
      null => null,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 34),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (origin != null) ...[origin, const SizedBox(height: 10)],
          // Scales down rather than wrapping: a broken year is the one thing
          // on this screen that must stay readable.
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
    );
  }
}

class _RevealBody extends StatelessWidget {
  const _RevealBody({
    required this.game,
    required this.onNextRound,
    required this.onLyrics,
    required this.hasLyrics,
    required this.showScores,
    this.sync,
  });

  final GameController game;
  final VoidCallback onNextRound;
  final VoidCallback onLyrics;

  /// Whether the song has words at all, null while nobody knows yet.
  final bool? hasLyrics;
  final bool showScores;

  /// The sync arrows while that mode is on.
  final Widget? sync;

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
            child: _LyricsButton(onLyrics: onLyrics, has: hasLyrics),
          ),
          if (sync case final panel?) ...[const SizedBox(height: 12), panel],
          if (showScores) ...[
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
          ],
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
    required this.lyricsScale,
    required this.onLyricsScale,
    required this.lyricsSync,
    required this.syncMode,
    required this.onSync,
    required this.hasLyrics,
    required this.showScores,
    required this.shortcuts,
    required this.columnShare,
    required this.onColumnShare,
    required this.slotShare,
    required this.onSlotShare,
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

  /// How big the words on the stage are, set from the menu or by two fingers
  /// on the words themselves.
  final double lyricsScale;
  final ValueChanged<double> onLyricsScale;

  /// How far ahead of the song they run, see [LyricsSyncStore], and whether
  /// the panel for setting it is in the column.
  final int lyricsSync;
  final bool syncMode;
  final ValueChanged<int> onSync;

  /// Whether the song has words at all, null while nobody knows yet.
  final bool? hasLyrics;

  /// Whether the scoreboard is on the stage at all, see [ShowScoresStore].
  final bool showScores;

  /// Whether the keyboard hints are worth the space, see [hasKeyboard]. They
  /// go in the column, which is the half for whoever runs the game - a key
  /// nobody in the room can press has no business on the stage.
  final bool shortcuts;

  /// The share of the screen the column takes, and the handle that changes it.
  final double columnShare;
  final ValueChanged<double> onColumnShare;

  /// The share of the column the reveal card takes, and its own handle.
  final double slotShare;
  final ValueChanged<double> onSlotShare;

  @override
  Widget build(BuildContext context) {
    final playing = game.phase == RoundPhase.playing;

    // The player sits across the bottom, under both halves. The band is one
    // row high, buttons on the left where the column's controls are, and the
    // track takes the rest of the screen - four times the width it had in the
    // column, which is the difference between finding a chorus and guessing
    // at it. The room above it is kept while a launch is still out, so a swap
    // does not pull the floor out from under the stage.
    final bar = game.playingInApp;
    final barRoom = bar || (playing && _looksInApp(game, spotify));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Whatever the handle was last dragged to. No floor and no cap but
        // the store's own: it is a decision somebody made with the screen in
        // front of them, which beats anything guessed from the width here.
        final side = constraints.maxWidth * columnShare;
        // Two fixed homes in the column, so nothing moves from round to
        // round: the slot on top is what to do or what came of it, the camera
        // sits at the bottom. The camera's height is 4:3 as far as the width
        // allows, capped at a third of the column - a projector is nowhere
        // near that cap.
        //
        // The slot is whatever its own handle was last dragged to. It used to
        // be a share with a cap in pixels; the cap was there so the answer
        // does not become a poster on a big screen, and that is now a
        // decision made with the screen in front of you ([SlotHeightStore]).
        final slot = constraints.maxHeight * slotShare;
        // As wide as the slot above it - the two boxes of the column are one
        // column, not two sizes. 4:3 as far as the height allows and cropped
        // rather than narrowed where it does not: what the scanner reads is
        // the camera's frame, not the painted preview.
        final cameraHeight = min(
          (side - 36) * 3 / 4,
          constraints.maxHeight * 0.33,
        );

        // Closed and between rounds there is nothing to look at, so the box
        // goes rather than sitting there as a grey placeholder. After a reveal
        // it stays as the way back to a camera that was closed by hand.
        final showCamera = camera != null || game.isRevealed;

        final round = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: side,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 12, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: slot,
                      child: _ActionSlot(
                        game: game,
                        onScan: onScan,
                        onReveal: game.reveal,
                      ),
                    ),
                    // The reveal card's own grip, for the same reason the
                    // split between the halves has one: how much of the
                    // column the answer deserves is a question about the room.
                    _SlotHandle(
                      onMove: (delta) => onSlotShare(
                        slotShare + delta / constraints.maxHeight,
                      ),
                    ),
                    // Under it the controls with the keys at their foot - and
                    // the camera over both when it is open. It is an overlay
                    // and not a block of its own on purpose: the keys stay
                    // exactly where they were and are covered, instead of
                    // sliding up every time a card is scanned.
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => Stack(
                          children: [
                            Positioned.fill(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _FitBody(
                                      center: false,
                                      padding: const EdgeInsets.only(top: 16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (syncMode) ...[
                                            _SyncPanel(
                                              offsetMs: lyricsSync,
                                              onSync: onSync,
                                            ),
                                            const SizedBox(height: 12),
                                          ],
                                          if (playing)
                                            _SongControls(
                                              game: game,
                                              spotify: spotify,
                                              onRedraw: onRedraw,
                                              onUndoRedraw: onUndoRedraw,
                                              hasLyrics: hasLyrics,
                                              inColumn: true,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (shortcuts) _ShortcutHints(game: game),
                                ],
                              ),
                            ),
                            if (showCamera)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                // Never taller than the room under the slot:
                                // the box is an overlay, and an overlay bigger
                                // than its stack is an overflow.
                                height: min(cameraHeight, box.maxHeight),
                                child: _CameraBox(
                                  camera: camera,
                                  onCode: onCode,
                                  onClose: onCloseCamera,
                                  onNextRound: onNextRound,
                                  withoutCards: game.withoutCards,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _SplitHandle(
              onMove: (delta) =>
                  onColumnShare(columnShare + delta / constraints.maxWidth),
            ),
            Expanded(
              child: _Stage(
                game: game,
                spotify: spotify,
                lyrics: lyrics,
                lyricsScale: lyricsScale,
                onLyricsScale: onLyricsScale,
                lyricsSync: lyricsSync,
                showScores: showScores,
              ),
            ),
          ],
        );

        if (!barRoom) return round;

        return Column(
          children: [
            Expanded(child: round),
            Padding(
              // Off the very bottom edge: a drag down there fights the
              // phone's own home gesture. And off the half above it, so the
              // band reads as the floor of the screen rather than as the
              // next row of the column.
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Visibility(
                visible: bar,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: SongProgressBar(session: spotify, inOneRow: true),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// What the keys do, for the one device that has them.
///
/// It sits at the foot of the column's controls rather than on the stage: a
/// key nobody in the room can press is of no use to the room, and the hint is
/// read once an evening and then never again. Only the keys that do something
/// right now are listed - the song can only be moved in a round that plays in
/// this tab.
class _ShortcutHints extends StatelessWidget {
  const _ShortcutHints({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = [
      for (final shortcut in GameShortcut.values)
        if (shortcut.isLive(game)) shortcut,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();

    // The whole block scales into the room it is given rather than wrapping
    // to the column's width: one chip is wider than a phone's column, so
    // wrapping only moved the overflow from the side to the bottom, where it
    // ran under the preview. Laid out at a width of its own and shrunk to
    // fit, the way every other panel here does it.
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 320,
          child: Wrap(
            spacing: 10,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              for (final shortcut in shown)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        child: Text(
                          shortcut.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      shortcut.does,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top of the side column: what to do now, or what came of it.
///
/// One fixed home for three things that never want to be on screen together -
/// the first scan, the reveal, and the year it produced - so the column does
/// not rearrange itself from round to round. The camera has its own place at
/// the bottom and does not displace this.
class _ActionSlot extends StatelessWidget {
  const _ActionSlot({
    required this.game,
    required this.onScan,
    required this.onReveal,
  });

  final GameController game;
  final VoidCallback onScan;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(24);

    // The year for whoever runs the game, beside the one on the stage: the
    // room reads the wall, and this says what the camera is about to replace.
    if (game.isRevealed) {
      return _ColumnYear(game: game);
    }

    final (icon, title, hint, onTap) = game.phase == RoundPhase.playing
        ? (
            Icons.visibility_outlined,
            'Reveal the year',
            game.withoutCards
                ? 'The next year waits below'
                : 'The camera then opens below',
            onReveal,
          )
        : game.withoutCards
        ? (
            Icons.casino_outlined,
            'Draw a year',
            '${game.fromYear} to ${game.toYear}, '
                '${game.playedYears.length} of '
                '${game.playableYears.length} played',
            onScan,
          )
        : (
            Icons.qr_code_scanner,
            'Scan a card',
            'Opens the camera below',
            onScan,
          );

    return Material(
      key: game.phase == RoundPhase.playing ? revealInColumnKey : null,
      color: game.phase == RoundPhase.playing
          ? scheme.primary
          : scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: _FitBody(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                icon,
                size: 44,
                color: game.phase == RoundPhase.playing
                    ? scheme.onPrimary
                    : scheme.onPrimaryContainer,
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: game.phase == RoundPhase.playing
                      ? scheme.onPrimary
                      : scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      (game.phase == RoundPhase.playing
                              ? scheme.onPrimary
                              : scheme.onPrimaryContainer)
                          .withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The answer, top left in the column: the year tinted by its decade, with the
/// song under it.
///
/// It is the only place the wide layout shows it. The stage keeps the words for
/// the whole round - they are the reason to put the game on a wall, and an
/// answer laid over them takes away what the room was reading. On a projector
/// this box is on the same wall anyway, so the room reads it here; next to it
/// the camera is already waiting for the next card.
class _ColumnYear extends StatelessWidget {
  const _ColumnYear({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = game.currentSong;
    final year = game.currentYear ?? song?.year ?? 0;
    final accent = decadeColor(year);

    // Where the song came from, which for a contest entry is what makes the
    // year read as the year of that contest. It was on the stage's card and
    // this is the only card left.
    final origin = _originLine(game, song);

    // The year a little smaller than it could be and the name a lot bigger
    // than it was: the year is four digits anybody reads at a glance, the
    // title is what the room actually talks about at the reveal.
    final yearText = Text(
      '$year',
      maxLines: 1,
      style: TextStyle(
        fontSize: 76,
        fontWeight: FontWeight.w800,
        height: 1,
        letterSpacing: -2,
        color: accent,
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent, width: 2),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // Two columns where the card is wider than it is tall: the year
          // beside the name rather than over it, which leaves the year twice
          // the height and the room twice the type. A narrow column - a phone
          // turned over - stacks them as before.
          final beside = box.maxWidth > box.maxHeight * 1.3;

          final name = [
            if (origin != null)
              Text(
                origin,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: beside ? TextAlign.start : TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: accent,
                  letterSpacing: 0.4,
                ),
              ),
            if (song != null) ...[
              Text(
                song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: beside ? TextAlign.start : TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: beside ? TextAlign.start : TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ];

          return _FitBody(
            padding: const EdgeInsets.all(16),
            child: beside
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: yearText,
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Flexible rather than Expanded: expanded, the name
                      // took the whole rest of the card and its left-aligned
                      // text left all the air on the right, which is the
                      // off-centre the card looked. Now the two of them are
                      // one block and the Row centres it.
                      Flexible(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: name,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(fit: BoxFit.scaleDown, child: yearText),
                      ...name,
                    ],
                  ),
          );
        },
      ),
    );
  }
}

/// The line between the two halves, and the grip that moves it.
///
/// A projector wants a wide stage and a laptop run by hand wants a wide
/// column, and which one the evening is depends on the room rather than on
/// anything the code can measure - so it is dragged, and remembered
/// ([ColumnWidthStore]).
class _SplitHandle extends StatelessWidget {
  const _SplitHandle({required this.onMove});

  /// The pixels the grip was dragged, positive to the right.
  final ValueChanged<double> onMove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      key: splitHandleKey,
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        // The drag is horizontal only, so a wide grip cannot be mistaken for
        // a tap on either half - and a finger on a tablet needs more than the
        // line it can see.
        onHorizontalDragUpdate: (details) => onMove(details.delta.dx),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 24,
          child: Center(
            child: Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line under the reveal card, and the grip that moves it.
///
/// The same decision as [_SplitHandle] turned ninety degrees: the card is the
/// reveal while the song runs and the answer afterwards, and how much of the
/// column that deserves depends on whether it is read from a sofa or from the
/// chair the laptop is on. So it is dragged, and remembered
/// ([SlotHeightStore]).
class _SlotHandle extends StatelessWidget {
  const _SlotHandle({required this.onMove});

  /// The pixels the grip was dragged, positive downwards.
  final ValueChanged<double> onMove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      key: slotHandleKey,
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        // Vertical only, so the grip cannot be mistaken for a tap on the card
        // above it - which is the reveal, and the one press on this screen
        // that must not happen by accident.
        onVerticalDragUpdate: (details) => onMove(details.delta.dy),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 22,
          child: Center(
            child: Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bottom of the side column, where the camera runs.
///
/// It is not on screen at all while a round plays - there is nothing to look
/// at and a grey placeholder is worse than the room the words get instead. It
/// comes back with the reveal, by itself, and a camera closed by hand leaves
/// the button that opens it again.
class _CameraBox extends StatelessWidget {
  const _CameraBox({
    required this.camera,
    required this.onCode,
    required this.onClose,
    required this.onNextRound,
    this.withoutCards = false,
  });

  final CameraBuilder? camera;
  final ValueChanged<String> onCode;
  final VoidCallback onClose;
  final VoidCallback onNextRound;

  /// In a game without cards there is never a camera here: the box is the
  /// button that draws the next year, and it says so rather than offering a
  /// scanner nobody has a card for.
  final bool withoutCards;

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

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onNextRound,
        child: _FitBody(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                withoutCards ? Icons.casino_outlined : Icons.qr_code_scanner,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                withoutCards ? 'Next year' : 'Next round',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
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
/// same as the sheet on the phone; the year card names the song once it is
/// out. In a round played in this tab they follow the song.
///
/// While the room guesses the words have the whole stage: nothing above them
/// and, with the scores off, nothing below. The year card is what takes the
/// top of it back at the reveal - the words give way to the answer, which is
/// the one moment the stage is allowed to rearrange itself.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.game,
    required this.spotify,
    required this.lyrics,
    required this.lyricsScale,
    required this.onLyricsScale,
    required this.lyricsSync,
    required this.showScores,
  });

  final GameController game;
  final SpotifySession spotify;
  final LyricsSource lyrics;

  /// How far ahead of the song the words run, see [LyricsSyncStore].
  final int lyricsSync;

  /// What the room asked for on top of the size the height gives, set from
  /// the menu or by two fingers on the words, and kept per device
  /// ([LyricsScaleStore]).
  final double lyricsScale;
  final ValueChanged<double> onLyricsScale;

  /// Whether the scores are along the bottom, see [ShowScoresStore]. Hidden,
  /// the words have the stage to themselves.
  final bool showScores;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = game.currentSong;
    final revealed = game.phase == RoundPhase.revealed;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Everything is a share of the height, which is what the device
        // varies: a 1080p wall has twice the room for words a 720p one has,
        // and a phone turned over has a third of either. Only the upper end
        // is capped, so a big picture does not turn the year into a poster -
        // there is no floor, because a phone's shares are below any floor a
        // projector would want, and every block scales what it holds down
        // rather than overflowing.
        final height = constraints.maxHeight;
        // A phone turned over, never a projector. The words are what the
        // stage is for, so on a short one everything else gives them room:
        // the scores take a smaller share and the line about tapping them
        // goes - whoever hands out points is holding the device and does not
        // read a wall to find that out.
        final short = height < 520;
        final tile = (height * (short ? 0.11 : 0.14)).clamp(0.0, 132.0);
        // The size the height gives, times what the room asked for. The cap
        // is the stage's, the factor is not: a wall far enough away can want
        // more than a 1080p share of it.
        final line = (height / 28).clamp(15.0, 36.0) * lyricsScale;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (song == null)
                const Expanded(child: _StageIdle())
              else ...[
                Expanded(
                  // The words scroll themselves, so a scrollbar on the wall
                  // is only noise. The edges fade rather than cut a line in
                  // half.
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
                      // The room inside the box is a share of it, not a set
                      // number of pixels: 28 above and 72 below are a tenth
                      // of a projector's box and most of a phone's 109.
                      child: LayoutBuilder(
                        builder: (context, box) => LyricsView(
                          key: ValueKey(song.key),
                          song: song,
                          source: lyrics,
                          session: game.playingInApp ? spotify : null,
                          syncMs: lyricsSync,
                          // Two fingers on the words set their size, the
                          // gesture anybody tries first on a text that is
                          // too small - the menu's two entries are the same
                          // setting for a screen with no touch.
                          scaleOf: () => lyricsScale,
                          onScale: onLyricsScale,
                          lineStyle: theme.textTheme.headlineSmall?.copyWith(
                            fontSize: line,
                            // Air between the lines: the whole text is up at
                            // once on a wall, and set tight it reads as a
                            // block rather than as lines to follow.
                            height: 1.5,
                          ),
                          padding: EdgeInsets.fromLTRB(
                            24,
                            (box.maxHeight * 0.05).clamp(2.0, 28.0),
                            24,
                            (box.maxHeight * 0.13).clamp(8.0, 72.0),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (showScores) ...[
                const SizedBox(height: 16),
                _SectionHeading(
                  title: revealed ? 'Who got it right?' : 'Scores',
                  targetScore: game.targetScore,
                ),
                if (revealed && !short) ...[
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
