import '../game/game_controller.dart';
import '../models/player.dart';
import '../models/song.dart';
import '../models/song_category.dart';

/// What goes over the link, and the only three kinds of it.
///
/// The phone runs the game and talks; the screen listens and draws. Nothing
/// goes the other way - a screen that could change the game would be a second
/// place where the state lives, and then there would be two of them to keep
/// in step.
sealed class SyncMessage {
  const SyncMessage();

  Map<String, Object?> toJson();

  /// Null for anything this build does not know - the relay's own `room` and
  /// `peers`, and a field from a newer phone. Never throws: a message nobody
  /// understands must not take the evening down.
  static SyncMessage? fromJson(Map<String, dynamic> json) =>
      switch (json['t']) {
        'state' => GameSnapshot.fromJson(json),
        'tick' => PlaybackTick.fromJson(json),
        'cmd' => RemoteCommand.fromJson(json),
        _ => null,
      };
}

/// The round as the screen draws it.
///
/// Sent whenever the game says something changed, which is a handful of times
/// a round - this is not a stream, the position has its own message for that.
class GameSnapshot extends SyncMessage {
  const GameSnapshot({
    required this.phase,
    required this.players,
    required this.targetScore,
    required this.showScores,
    this.year,
    this.title,
    this.artist,
    this.deck,
    this.country,
    this.place,
    this.trackId,
    this.launchMessage,
    this.hasLyrics,
    this.playingInApp = false,
    this.sessionReady = false,
    this.launching = false,
    this.canRedraw = false,
    this.canUndoRedraw = false,
    this.fromYear,
    this.toYear,
    this.playedYears = const [],
    this.playableYears = const [],
    this.syncMode = false,
  });

  factory GameSnapshot.of(
    GameController game, {
    required bool showScores,
    required bool sessionReady,
    required bool syncMode,
    bool? hasLyrics,
  }) {
    final song = game.currentSong;
    return GameSnapshot(
      phase: game.phase,
      players: [
        for (final player in game.players)
          (name: player.name, score: player.score),
      ],
      targetScore: game.targetScore,
      showScores: showScores,
      year: game.currentYear,
      title: song?.title,
      artist: song?.artist,
      deck: game.currentCategory?.name,
      country: song?.country,
      place: song?.place,
      trackId: song?.spotifyTrackId,
      launchMessage: game.launchMessage,
      hasLyrics: hasLyrics,
      playingInApp: game.playingInApp,
      sessionReady: sessionReady,
      launching: game.launching,
      canRedraw: game.canRedraw,
      canUndoRedraw: game.canUndoRedraw,
      fromYear: game.fromYear,
      toYear: game.toYear,
      playedYears: game.playedYears.toList(),
      playableYears: game.playableYears,
      syncMode: syncMode,
    );
  }

  factory GameSnapshot.fromJson(Map<String, dynamic> json) => GameSnapshot(
    phase: RoundPhase.values.firstWhere(
      (phase) => phase.name == json['phase'],
      orElse: () => RoundPhase.idle,
    ),
    players: [
      for (final player in (json['players'] as List? ?? const []))
        (
          name: (player as Map)['name'] as String? ?? '',
          score: player['score'] as int? ?? 0,
        ),
    ],
    targetScore: json['targetScore'] as int? ?? 10,
    showScores: json['showScores'] as bool? ?? true,
    year: json['year'] as int?,
    title: json['title'] as String?,
    artist: json['artist'] as String?,
    deck: json['deck'] as String?,
    country: json['country'] as String?,
    place: json['place'] as int?,
    trackId: json['trackId'] as String?,
    launchMessage: json['launchMessage'] as String?,
    hasLyrics: json['hasLyrics'] as bool?,
    playingInApp: json['playingInApp'] as bool? ?? false,
    sessionReady: json['sessionReady'] as bool? ?? false,
    launching: json['launching'] as bool? ?? false,
    canRedraw: json['canRedraw'] as bool? ?? false,
    canUndoRedraw: json['canUndoRedraw'] as bool? ?? false,
    fromYear: json['fromYear'] as int?,
    toYear: json['toYear'] as int?,
    playedYears: [
      for (final year in (json['playedYears'] as List? ?? const []))
        if (year is int) year,
    ],
    playableYears: [
      for (final year in (json['playableYears'] as List? ?? const []))
        if (year is int) year,
    ],
    syncMode: json['syncMode'] as bool? ?? false,
  );

  final RoundPhase phase;
  final List<({String name, int score})> players;
  final int targetScore;

  /// Whether the scoreboard is on the stage at all. The switch is the game's,
  /// so it travels with the snapshot rather than sitting on the screen.
  final bool showScores;

  final int? year;
  final String? title;
  final String? artist;

  /// The deck's name, which is what makes a year read as the year of that
  /// contest at the reveal.
  final String? deck;
  final String? country;
  final int? place;

  /// Only so the screen can look the words up itself - it asks LRCLIB with
  /// the title and the artist, exactly as the phone does.
  final String? trackId;

  final String? launchMessage;
  final bool? hasLyrics;
  final bool playingInApp;

  /// Whether the phone's session plays here at all. The screen needs it for
  /// the same reason the phone does: a launch that is still out leaves the
  /// band and the layout in place instead of blinking them away.
  final bool sessionReady;

  final bool launching;
  final bool canRedraw;
  final bool canUndoRedraw;

  /// The range of a game without cards, and how far through it the game is -
  /// the screen says `1970 to 2026, 4 of 57 played` where the card game says
  /// `Scan a card`, and it cannot work any of that out itself: the catalogs
  /// are on the phone. Both years null is a game played with the cards, which
  /// is what [withoutCards] reads.
  final int? fromYear;
  final int? toYear;
  final List<int> playedYears;
  final List<int> playableYears;

  bool get withoutCards => fromYear != null && toYear != null;

  final bool syncMode;

  /// The song of the round as a [Song] again, so the screen can hand it to
  /// the lyrics source and the reveal card unchanged. Null between rounds.
  ///
  /// The year is the card's year rather than the song's release - which for
  /// everything the reveal shows is the same number.
  Song? get song {
    final name = title;
    final by = artist;
    if (name == null || by == null) return null;
    return Song(
      title: name,
      artist: by,
      year: year ?? 0,
      spotifyTrackId: trackId,
      country: country,
      place: place,
    );
  }

  /// A deck that holds nothing: the screen never draws from it, it only reads
  /// the name off the reveal.
  SongCategory? get category => deck == null
      ? null
      : SongCategory(
          id: 'mirror',
          name: deck!,
          description: '',
          songs: const [],
        );

  List<GamePlayer> get roster => [
    for (final player in players)
      GamePlayer(name: player.name, score: player.score),
  ];

  @override
  Map<String, Object?> toJson() => {
    't': 'state',
    'phase': phase.name,
    'players': [
      for (final player in players)
        {'name': player.name, 'score': player.score},
    ],
    'targetScore': targetScore,
    'showScores': showScores,
    if (year != null) 'year': year,
    if (title != null) 'title': title,
    if (artist != null) 'artist': artist,
    if (deck != null) 'deck': deck,
    if (country != null) 'country': country,
    if (place != null) 'place': place,
    if (trackId != null) 'trackId': trackId,
    if (launchMessage != null) 'launchMessage': launchMessage,
    if (hasLyrics != null) 'hasLyrics': hasLyrics,
    'playingInApp': playingInApp,
    'sessionReady': sessionReady,
    'launching': launching,
    'canRedraw': canRedraw,
    'canUndoRedraw': canUndoRedraw,
    if (fromYear != null) 'fromYear': fromYear,
    if (toYear != null) 'toYear': toYear,
    if (playedYears.isNotEmpty) 'playedYears': playedYears,
    if (playableYears.isNotEmpty) 'playableYears': playableYears,
    'syncMode': syncMode,
  };
}

/// Where the song is, every couple of seconds.
///
/// The screen carries the position forward on its own clock in between, the
/// same way both Spotify sessions carry their own reports forward. What it
/// must not do is read [at] against its own clock: two devices are two clocks
/// and can be seconds apart, so the arrival is the timestamp and the
/// difference is absorbed by the sync offset the room sets anyway.
class PlaybackTick extends SyncMessage {
  const PlaybackTick({
    required this.positionMs,
    required this.durationMs,
    required this.playing,
  });

  factory PlaybackTick.fromJson(Map<String, dynamic> json) => PlaybackTick(
    positionMs: json['positionMs'] as int? ?? 0,
    durationMs: json['durationMs'] as int? ?? 0,
    playing: json['playing'] as bool? ?? false,
  );

  final int positionMs;
  final int durationMs;
  final bool playing;

  @override
  Map<String, Object?> toJson() => {
    't': 'tick',
    'positionMs': positionMs,
    'durationMs': durationMs,
    'playing': playing,
  };
}

/// The settings that belong to the screen rather than to the game, stepped
/// from the phone.
///
/// How big the words are and how far they run ahead of the song are
/// statements about this room and this screen - how far the sofa is, what the
/// television does to the picture - so they live where the words are drawn and
/// the remote only nudges them. A second screen brings its own.
///
/// `columnWider`/`columnNarrower` and `slotTaller`/`slotShorter` are the same
/// idea for the column's own two handles: a television has no pointer to
/// drag them with, so the phone steps them instead, exactly as it already
/// does for the words. `uiBigger`/`uiSmaller` cover the rest of the layout -
/// a Fire TV Stick sits closer to the room than a projector does, and the
/// furniture sized for one looks oversized on the other.
enum RemoteStep {
  wordsBigger,
  wordsSmaller,
  wordsEarlier,
  wordsLater,
  columnWider,
  columnNarrower,
  slotTaller,
  slotShorter,
  uiBigger,
  uiSmaller,
}

class RemoteCommand extends SyncMessage {
  const RemoteCommand(this.step);

  factory RemoteCommand.fromJson(Map<String, dynamic> json) => RemoteCommand(
    RemoteStep.values.firstWhere(
      (step) => step.name == json['step'],
      orElse: () => RemoteStep.wordsBigger,
    ),
  );

  final RemoteStep step;

  @override
  Map<String, Object?> toJson() => {'t': 'cmd', 'step': step.name};
}
