import '../data/year_database.dart';
import '../game/game_controller.dart';
import '../models/player.dart';
import '../models/song.dart';
import '../models/song_category.dart';
import '../music/spotify_playback.dart';
import 'sync_messages.dart';

/// The game as the screen sees it: everything a round shows, nothing that
/// decides anything.
///
/// It is a [GameController] on purpose rather than a value object of its own.
/// The screen draws the landscape layout - the same widgets, down to the
/// handles and the fitted text - and those read a controller. A second kind
/// of round built from a second kind of state would be the same layout
/// written twice, and the second copy would start drifting the day somebody
/// moves a block in the first.
///
/// What makes it safe is that nothing here *does* anything: every action a
/// widget could reach is dead ([reveal], the points), because the game is on
/// the phone and a screen that revealed by itself would be a second truth.
/// The fields it sets are the ones the round already kept in the open.
class MirrorGame extends GameController {
  MirrorGame({required super.years, required SongCategory placeholder})
    : super(players: <GamePlayer>[], categories: [placeholder]);

  /// A mirror with nothing to show yet - what the screen is before the first
  /// snapshot arrives.
  factory MirrorGame.empty(YearDatabase years) => MirrorGame(
    years: years,
    placeholder: SongCategory(
      id: 'mirror',
      name: '',
      description: '',
      songs: const [],
    ),
  );

  int _targetScore = 10;
  bool _canRedraw = false;
  bool _canUndoRedraw = false;
  bool _launching = false;
  bool _withoutCards = false;

  /// True once a snapshot has arrived. Before that the screen has a code to
  /// show and nothing else.
  bool get hasRound => _hasRound;
  bool _hasRound = false;

  @override
  int get targetScore => _targetScore;

  @override
  bool get canRedraw => _canRedraw;

  @override
  bool get canUndoRedraw => _canUndoRedraw;

  @override
  bool get launching => _launching;

  @override
  bool get withoutCards => _withoutCards;

  /// Takes the round over from the phone.
  void apply(GameSnapshot snapshot) {
    _hasRound = true;
    phase = snapshot.phase;
    currentYear = snapshot.year;
    currentSong = snapshot.song;
    currentCategory = snapshot.category;
    launchMessage = snapshot.launchMessage;
    playingInApp = snapshot.playingInApp;
    _targetScore = snapshot.targetScore;
    _canRedraw = snapshot.canRedraw;
    _canUndoRedraw = snapshot.canUndoRedraw;
    _launching = snapshot.launching;
    _withoutCards = snapshot.withoutCards;
    _applyRoster(snapshot);
    notifyListeners();
  }

  /// The players, kept in the list the controller was built with - the tiles
  /// read `players`, and replacing the list would leave them on the old one.
  /// Scores are moved in place for the same reason.
  void _applyRoster(GameSnapshot snapshot) {
    while (players.length > snapshot.players.length) {
      players.removeLast();
    }
    for (var i = 0; i < snapshot.players.length; i++) {
      final from = snapshot.players[i];
      if (i < players.length) {
        if (players[i].name == from.name) {
          players[i].score = from.score;
          continue;
        }
        players[i] = GamePlayer(name: from.name, score: from.score);
        continue;
      }
      players.add(GamePlayer(name: from.name, score: from.score));
    }
  }

  // --- everything a finger could reach, and none of it does anything -------
  //
  // Nobody can tap a television, but a laptop standing in for one can be
  // tapped, and the stage's year card and score tiles are buttons. Pressing
  // one must change the screen's mind about the round rather than the game's.

  @override
  void reveal() {}

  @override
  void addPoint(GamePlayer player) {}

  @override
  void removePoint(GamePlayer player) {}

  @override
  void nextRound() {}

  @override
  void cancelRound() {}

  @override
  bool redraw() => false;

  @override
  bool undoRedraw() => false;

  @override
  ScanOutcome scan(String rawCode) => ScanOutcome.unknownCode;

  @override
  Future<void> startPlayback() async {}

  @override
  Future<void> reopen() async {}
}

/// The player as the screen sees it: a position that runs, and no control.
///
/// The round plays on the phone - out of its tab or out of its Spotify app -
/// so there is nothing here to pause or seek. What the screen needs is the
/// position, because the words follow it and the band draws it, and that
/// arrives every couple of seconds and runs on the clock in between.
class MirrorSession extends SpotifySession {
  MirrorSession({DateTime Function() now = DateTime.now}) : _now = now;

  final DateTime Function() _now;

  int _positionMs = 0;
  int _durationMs = 0;
  bool _isPlaying = false;
  late DateTime _at = _now();

  /// Whether the phone's own session plays here, which is what the layout
  /// reads to keep the band in place through a launch.
  bool _ready = false;

  @override
  SpotifyConnection get connection =>
      _ready ? SpotifyConnection.ready : SpotifyConnection.unavailable;

  @override
  String? get error => null;

  @override
  String get offer => '';

  @override
  bool get isPlaying => _isPlaying;

  @override
  String? get playbackError => null;

  @override
  Duration get duration => Duration(milliseconds: _durationMs);

  @override
  Duration get position {
    var ms = _positionMs;
    if (_isPlaying) ms += _now().difference(_at).inMilliseconds;
    if (_durationMs > 0 && ms > _durationMs) ms = _durationMs;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  void readyIs(bool ready) {
    if (_ready == ready) return;
    _ready = ready;
    notifyListeners();
  }

  /// Takes a report from the phone.
  ///
  /// The arrival is the timestamp, never the phone's own: two devices are two
  /// clocks and can be seconds apart. What that costs is the trip through the
  /// relay, tens of milliseconds, and it is absorbed by the sync offset the
  /// room sets against the picture anyway.
  void apply(PlaybackTick tick) {
    _positionMs = tick.positionMs;
    _durationMs = tick.durationMs;
    _isPlaying = tick.playing;
    _at = _now();
    notifyListeners();
  }

  /// The song is over there, and so is every way of moving it.
  @override
  Future<void> restore() async {}

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> prepare() async {}

  @override
  Future<bool> play(Song song) async => false;

  @override
  Future<void> togglePause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}
}
