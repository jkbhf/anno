import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/game_store.dart';
import '../data/year_database.dart';
import '../models/player.dart';
import '../models/song.dart';
import '../models/song_category.dart';
import '../music/spotify_launcher.dart';

/// The course of one round.
enum RoundPhase {
  /// Waiting for the next QR code.
  idle,

  /// The song is picked, the countdown is running.
  countdown,

  /// Spotify was opened, the group is guessing.
  playing,

  /// Year and song are revealed, points are handed out.
  revealed,

  /// Someone reached the score target.
  finished,
}

/// What a scanned code triggered.
enum ScanOutcome {
  /// Year recognized, song found, countdown running.
  started,

  /// The code is in no database - its year has to be entered.
  unknownCode,

  /// Year recognized, but the category has no song for it.
  noSongForYear,
}

/// The state of one game on the shared device.
class GameController extends ChangeNotifier {
  GameController({
    required this.players,
    required this.categories,
    required this.years,
    this.targetScore = 10,
    SpotifyLauncher launcher = const UrlSpotifyLauncher(),
    Future<void> Function(SavedGame)? persist,
    Random? random,
  }) : assert(categories.isNotEmpty, 'A game needs at least one category.'),
       _launcher = launcher,
       _persist = persist,
       _random = random ?? Random();

  /// How long a `resumed` is still ignored after opening Spotify.
  ///
  /// When switching to another app some devices briefly report `resumed` before
  /// they pause. Without this guard the round would reveal immediately.
  static const Duration ignoreResumeAfterLaunch = Duration(milliseconds: 1200);

  final List<GamePlayer> players;

  /// The decks in play. With more than one, every round draws from a category
  /// picked at random among those that have a song for the scanned year.
  final List<SongCategory> categories;

  final YearDatabase years;
  final int targetScore;

  final SpotifyLauncher _launcher;
  final Future<void> Function(SavedGame)? _persist;
  final Random _random;

  /// Songs already played, so a game does not repeat itself.
  final Set<String> _played = <String>{};

  RoundPhase phase = RoundPhase.idle;

  /// The song of the running round - secret until [RoundPhase.revealed].
  Song? currentSong;

  /// The category [currentSong] was drawn from.
  SongCategory? currentCategory;

  /// The year of the scanned code.
  int? currentYear;

  /// The last scanned raw value, used to fill in unknown codes.
  String? lastScannedCode;

  /// Note from handing over to Spotify, otherwise null.
  String? launchMessage;

  DateTime? _launchedAt;

  bool get isRevealed =>
      phase == RoundPhase.revealed || phase == RoundPhase.finished;

  /// Players at the highest score from the target upwards. Several on a tie.
  List<GamePlayer> get winners {
    final reached = players.where((p) => p.score >= targetScore).toList();
    if (reached.isEmpty) return const [];
    final best = reached.map((p) => p.score).reduce(max);
    return [
      for (final p in reached)
        if (p.score == best) p,
    ];
  }

  /// Sorted by score, ties keep the order they were entered in.
  List<GamePlayer> get ranking {
    final sorted = [...players];
    sorted.sort((a, b) => b.score.compareTo(a.score));
    return sorted;
  }

  SavedGame get snapshot => SavedGame(
    players: players,
    categoryIds: [for (final category in categories) category.id],
    targetScore: targetScore,
  );

  /// Handles a scanned QR code and starts the countdown on success.
  ScanOutcome scan(String rawCode) {
    lastScannedCode = rawCode;
    launchMessage = null;

    final year = years.yearFor(rawCode);
    if (year == null) {
      notifyListeners();
      return ScanOutcome.unknownCode;
    }

    final draw = _draw(year);
    if (draw == null) {
      currentYear = year;
      currentSong = null;
      currentCategory = null;
      notifyListeners();
      return ScanOutcome.noSongForYear;
    }

    currentYear = year;
    currentSong = draw.song;
    currentCategory = draw.category;
    _played.add(_playedKey(draw.category, draw.song));
    phase = RoundPhase.countdown;
    notifyListeners();
    return ScanOutcome.started;
  }

  /// Hands over to Spotify. If that fails the round reveals right away - better
  /// to play on without music than to hang in an empty waiting phase.
  Future<void> startPlayback() async {
    final song = currentSong;
    if (song == null || phase != RoundPhase.countdown) return;

    phase = RoundPhase.playing;
    _launchedAt = DateTime.now();
    notifyListeners();

    final result = await _launcher.open(song);
    launchMessage = result.message;
    if (!result.opened) {
      phase = RoundPhase.revealed;
      _launchedAt = null;
    }
    notifyListeners();
  }

  /// Hands the current song to Spotify again.
  ///
  /// The way out on the web: a blocked popup reaches the app as a success, so
  /// the playing screen offers this as a button, where the tap counts as the
  /// user gesture the browser wants.
  Future<void> reopenInSpotify() async {
    final song = currentSong;
    if (song == null || phase != RoundPhase.playing) return;
    final result = await _launcher.open(song);
    launchMessage = result.message;
    notifyListeners();
  }

  /// Coming back from Spotify: the year is revealed.
  void onAppResumed({DateTime? now}) {
    if (phase != RoundPhase.playing) return;
    final launchedAt = _launchedAt;
    if (launchedAt != null &&
        (now ?? DateTime.now()).difference(launchedAt) <
            ignoreResumeAfterLaunch) {
      return;
    }
    reveal();
  }

  /// Reveals by hand - in case the switch back was not detected.
  void reveal() {
    if (phase != RoundPhase.playing) return;
    phase = RoundPhase.revealed;
    _launchedAt = null;
    notifyListeners();
  }

  /// Aborts the running round without handing out points.
  void cancelRound() {
    if (phase == RoundPhase.finished) return;
    currentSong = null;
    currentCategory = null;
    currentYear = null;
    launchMessage = null;
    _launchedAt = null;
    phase = RoundPhase.idle;
    notifyListeners();
  }

  void addPoint(GamePlayer player) => _changeScore(player, 1);

  void removePoint(GamePlayer player) => _changeScore(player, -1);

  void _changeScore(GamePlayer player, int delta) {
    if (!isRevealed) return;
    final next = player.score + delta;
    if (next < 0) return;
    player.score = next;
    notifyListeners();
    _save();
  }

  /// Ends the round. If the score target is reached, the game is over.
  void nextRound() {
    if (phase != RoundPhase.revealed) return;
    currentSong = null;
    currentCategory = null;
    currentYear = null;
    launchMessage = null;
    phase = winners.isEmpty ? RoundPhase.idle : RoundPhase.finished;
    notifyListeners();
  }

  void resetScores() {
    for (final player in players) {
      player.score = 0;
    }
    _played.clear();
    currentSong = null;
    currentCategory = null;
    currentYear = null;
    launchMessage = null;
    phase = RoundPhase.idle;
    notifyListeners();
    _save();
  }

  /// Draws a song for that year: first a category at random, then one of its
  /// songs.
  ///
  /// Categories that still hold something unplayed are preferred over ones
  /// that are used up, and every category gets the same chance regardless of
  /// how many songs it has for the year - otherwise a well filled deck would
  /// crowd out a thin one.
  ///
  /// Within the category the song is drawn by [Song.tier]: the core of a year
  /// comes up [_tierOneWeight] times as often as its long tail. In a game a
  /// year is usually scanned once or twice, so the tier decides which of its
  /// songs the room gets to hear at all.
  ///
  /// Once everything is used up the year starts over: a repeat beats a dead
  /// card.
  ({SongCategory category, Song song})? _draw(int year) {
    final withFresh = <SongCategory>[];
    final withAny = <SongCategory>[];

    for (final category in categories) {
      final pool = category.songsForYear(year);
      if (pool.isEmpty) continue;
      withAny.add(category);
      if (pool.any((song) => !_played.contains(_playedKey(category, song)))) {
        withFresh.add(category);
      }
    }

    final candidates = withFresh.isNotEmpty ? withFresh : withAny;
    if (candidates.isEmpty) return null;

    final category = candidates[_random.nextInt(candidates.length)];
    final pool = category.songsForYear(year);
    final fresh = [
      for (final song in pool)
        if (!_played.contains(_playedKey(category, song))) song,
    ];
    final songs = fresh.isNotEmpty ? fresh : pool;

    return (category: category, song: _pickWeighted(songs));
  }

  /// How much more often a `tier: 1` song is drawn than a `tier: 2` one.
  static const int _tierOneWeight = 3;

  static int _weightOf(Song song) => song.tier == 1 ? _tierOneWeight : 1;

  /// Picks from a non-empty list, each song weighted by its tier.
  Song _pickWeighted(List<Song> songs) {
    var total = 0;
    for (final song in songs) {
      total += _weightOf(song);
    }

    var roll = _random.nextInt(total);
    for (final song in songs) {
      roll -= _weightOf(song);
      if (roll < 0) return song;
    }
    return songs.last;
  }

  /// The same song can sit in two categories - it counts as played per deck.
  static String _playedKey(SongCategory category, Song song) =>
      '${category.id}|${song.key}';

  void _save() {
    final persist = _persist;
    if (persist == null) return;
    unawaited(persist(snapshot));
  }
}
