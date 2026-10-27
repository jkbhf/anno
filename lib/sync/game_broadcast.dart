import 'dart:async';

import '../game/game_controller.dart';
import '../music/spotify_playback.dart';
import 'sync_messages.dart';
import 'tv_link.dart';

/// Keeps the screen's copy of the round in step with the phone's.
///
/// Two rhythms, because the round and the song move at different speeds: the
/// round is sent whenever the game says something changed - a handful of times
/// a round - and where the song is goes out on a timer while it plays. The
/// screen carries the position forward on its own clock in between, so this
/// is a correction rather than a stream.
///
/// It also sends the whole round whenever a screen turns up, which is both a
/// first pairing and a screen that reloaded: everything the screen knows, it
/// knows because it was told.
class GameBroadcast {
  GameBroadcast({
    required this.link,
    required this.game,
    required this.session,
    required this.snapshot,
    this.every = const Duration(seconds: 2),
  });

  final TvLink link;
  final GameController game;
  final SpotifySession session;

  /// The round as it stands, asked for rather than built here: half of what
  /// the screen draws - whether the scores are up, whether the song has
  /// words - belongs to the screen that is showing it and not to the game.
  final GameSnapshot Function() snapshot;

  /// How often the position goes out while a song plays.
  final Duration every;

  Timer? _timer;
  bool _running = false;

  void start() {
    if (_running) return;
    _running = true;
    game.addListener(_onGame);
    link.addListener(_onLink);
    link.onPeer = sendAll;
    _onGame();
  }

  void stop() {
    if (!_running) return;
    _running = false;
    game.removeListener(_onGame);
    link.removeListener(_onLink);
    if (link.onPeer == sendAll) link.onPeer = null;
    _timer?.cancel();
    _timer = null;
  }

  /// The round and the position in one, for a screen that has just arrived
  /// and knows nothing.
  void sendAll() {
    link.send(snapshot());
    _sendTick();
  }

  void _onGame() {
    link.send(snapshot());
    // A position that moved with the round - a new song, a seek, a pause -
    // should not wait out the timer.
    _sendTick();
    _keepTime();
  }

  void _onLink() {
    if (link.isPaired) return;
    // Nothing to keep in step with: the timer is the one thing here that
    // costs something while the line is down.
    _timer?.cancel();
    _timer = null;
  }

  void _keepTime() {
    final wanted = game.phase == RoundPhase.playing && game.playingInApp;
    if (!wanted) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(every, (_) => _sendTick());
  }

  void _sendTick() {
    link.send(
      PlaybackTick(
        positionMs: session.position.inMilliseconds,
        durationMs: session.duration.inMilliseconds,
        playing: session.isPlaying,
      ),
    );
  }
}
