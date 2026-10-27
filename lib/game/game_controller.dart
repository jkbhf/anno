import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/game_store.dart';
import '../data/year_database.dart';
import '../models/player.dart';
import '../models/song.dart';
import '../models/song_category.dart';
import '../music/music_service.dart';
import '../music/song_launcher.dart';
import '../music/spotify_launcher.dart';

/// The course of one round.
enum RoundPhase {
  /// Waiting for the next QR code.
  idle,

  /// The song is picked, the countdown is running.
  countdown,

  /// The song was handed over, the group is guessing.
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
    this.weights = const {},
    this.targetScore = 10,
    this.service = MusicService.spotify,
    SongLauncher launcher = const UrlSpotifyLauncher(),
    SongLauncher? linkLauncher,
    Future<void> Function(SavedGame)? persist,
    Future<void> Function()? discard,
    Future<void> Function()? stopMusic,
    void Function(Set<String> played)? onPlayedChanged,
    Iterable<String> played = const [],
    void Function(Set<String> skipped)? onSkippedChanged,
    Iterable<String> skipped = const [],
    this.fromYear,
    this.toYear,
    Iterable<int> playedYears = const [],
    Random? random,
  }) : assert(categories.isNotEmpty, 'A game needs at least one category.'),
       _launcher = launcher,
       _linkLauncher = linkLauncher ?? launcher,
       _persist = persist,
       _discard = discard,
       _stopMusic = stopMusic,
       _onPlayedChanged = onPlayedChanged,
       _onSkippedChanged = onSkippedChanged,
       _random = random ?? Random() {
    _played.addAll(played);
    _skipped.addAll(skipped);
    _playedYears.addAll(playedYears);
  }

  /// How long a `resumed` is still ignored after opening Spotify.
  ///
  /// When switching to another app some devices briefly report `resumed` before
  /// they pause. Without this guard the round would reveal immediately.
  static const Duration ignoreResumeAfterLaunch = Duration(milliseconds: 1200);

  final List<GamePlayer> players;

  /// The decks in play. With more than one, every round draws from a category
  /// picked at random among those that have a song for the scanned year,
  /// weighted by [weightOf].
  final List<SongCategory> categories;

  /// How often each deck comes up against the others, by category id - set on
  /// the category screen. A deck that is missing counts as 1.
  final Map<String, int> weights;

  /// The draw weight of [category], at least 1: a deck nobody wants to hear
  /// is one to untick, not one to keep at zero.
  int weightOf(SongCategory category) => max(1, weights[category.id] ?? 1);

  final YearDatabase years;
  final int targetScore;

  /// The years a game without cards draws from, both null for a game played
  /// with the printed cards. See [nextYear].
  final int? fromYear;
  final int? toYear;

  /// Whether this game draws its years itself instead of reading them off a
  /// card. The cards are the game; this is the game without them - in a car,
  /// on a sofa, or when the box is in the other flat.
  bool get withoutCards => fromYear != null && toYear != null;

  /// The years of the range this game has already drawn.
  ///
  /// Kept with the game and not per device: a year does not come twice while
  /// the range still has one nobody has heard, and a new game runs through the
  /// whole range again - which is the opposite of how the songs are
  /// remembered ([_played]), and deliberately so. A range of thirty years
  /// would otherwise be used up for good after two evenings.
  final Set<int> _playedYears = <int>{};

  Set<int> get playedYears => {..._playedYears};

  /// Where the songs are handed over to. The launcher is what actually goes
  /// there; this decides which songs can be drawn at all, see [songsFor].
  final MusicService service;

  final SongLauncher _launcher;

  /// What [reopen] goes through: the link, never the in-app player. Its button
  /// is only there when the song did not play here, so trying the player again
  /// would only fail the same way a second time.
  final SongLauncher _linkLauncher;

  final Future<void> Function(SavedGame)? _persist;

  /// Drops the saved game - a finished one is nothing to resume.
  final Future<void> Function()? _discard;

  /// Silences the in-app player, for a song whose launch came back after its
  /// round was already over.
  final Future<void> Function()? _stopMusic;

  /// Told the whole of [played] whenever it changes - a song went out, or a
  /// used up year started over - for the memory across games in
  /// `PlayedSongsStore`.
  final void Function(Set<String> played)? _onPlayedChanged;

  /// Told the whole of [skipped] whenever a song is swapped away, for the
  /// memory across games in `SkippedSongsStore`.
  final void Function(Set<String> skipped)? _onSkippedChanged;

  final Random _random;

  /// Songs already played - by this game and, through `PlayedSongsStore`, by
  /// every game on this device before it. A song in here does not come back
  /// until the rest of its year in its deck has been heard, see [_draw]. Also
  /// part of the saved game, so a resume after Android killed the app does not
  /// start every year over.
  final Set<String> _played = <String>{};

  /// The [Song.key]s of songs a round swapped away with [redraw] - the room
  /// did not know them. Without the deck: a song nobody knows is unknown in
  /// every deck it sits in. Such a song is drawn like the long tail of its
  /// year from then on, see [_weightOf]; it stays in the deck.
  final Set<String> _skipped = <String>{};

  /// The swap [undoRedraw] takes back: the song swapped away, where it came
  /// from, what the swap changed in the memories, and the song it brought.
  ({
    Song from,
    SongCategory fromCategory,
    bool skippedByIt,
    Song to,
    SongCategory toCategory,
    bool toWasPlayed,
  })?
  _lastRedraw;

  /// The song that went out last, so a year that starts over does not open
  /// with the song it just ended on.
  String? _lastPlayedKey;

  /// True while a launch is on its way. No second one starts then, and a
  /// `resumed` during it says nothing about coming back from Spotify.
  bool _launching = false;

  bool _disposed = false;

  /// The round that ended the game, kept for [undoFinish].
  ({Song song, SongCategory category, int year})? _finishingRound;

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

  /// Whether the round's song is coming out of this page instead of out of
  /// Spotify. Set from what the launch actually did, never from what the
  /// session claims about itself: a ready session still fails on a track the
  /// account cannot play, and the link is what runs then. The playing screen
  /// branches on this, so a fallback that nobody noticed would leave the round
  /// without its way back to Spotify.
  bool playingInApp = false;

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
    categoryWeights: {
      for (final category in categories) category.id: weightOf(category),
    },
    targetScore: targetScore,
    played: [..._played],
    fromYear: fromYear,
    toYear: toYear,
    playedYears: [..._playedYears],
  );

  /// The keys of the songs this game has played, see [playedKey].
  Set<String> get played => {..._played};

  /// The keys of the songs swapped away on this device, see [_skipped].
  Set<String> get skipped => {..._skipped};

  /// The years of the range that some chosen deck can actually play.
  ///
  /// A year without a song would be a round that opens with "draw another
  /// card" - and without cards there is nothing to draw, so such a year is
  /// never picked in the first place. [songsFor] is what decides, so a year
  /// whose only songs this service cannot play counts as empty too.
  List<int> get playableYears {
    final from = fromYear;
    final to = toYear;
    if (from == null || to == null) return const [];
    return [
      for (var year = min(from, to); year <= max(from, to); year++)
        if (categories.any((c) => songsFor(c, year).isNotEmpty)) year,
    ];
  }

  /// The next year of a game without cards, picked at random among those the
  /// range has not played yet - and null where the range holds no playable
  /// year at all.
  ///
  /// `startedOver` is true for the draw that empties the memory again: every
  /// year of the range has been heard, so the next pass begins. The screen
  /// says so, because a room that is keeping track deserves to know the round
  /// it is on is a repeat rather than a slip.
  ({int year, bool startedOver})? nextYear() {
    final playable = playableYears;
    if (playable.isEmpty) return null;

    var pool = [
      for (final year in playable)
        if (!_playedYears.contains(year)) year,
    ];
    var startedOver = false;
    if (pool.isEmpty) {
      _playedYears.clear();
      pool = playable;
      startedOver = true;
    }
    return (year: pool[_random.nextInt(pool.length)], startedOver: startedOver);
  }

  /// Handles a scanned QR code and starts the countdown on success.
  ScanOutcome scan(String rawCode) {
    lastScannedCode = rawCode;
    _lastRedraw = null;
    launchMessage = null;
    playingInApp = false;

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

    // Not marked as played yet: a countdown that gets closed plays nothing,
    // and the song - usually one of the core of its year - stays in the pool.
    currentYear = year;
    currentSong = draw.song;
    currentCategory = draw.category;
    phase = RoundPhase.countdown;
    notifyListeners();
    return ScanOutcome.started;
  }

  /// Hands over to Spotify. If that fails the round reveals right away - better
  /// to play on without music than to hang in an empty waiting phase.
  Future<void> startPlayback() async {
    final song = currentSong;
    final category = currentCategory;
    if (song == null || category == null || phase != RoundPhase.countdown) {
      return;
    }

    phase = RoundPhase.playing;
    _launchedAt = DateTime.now();
    _markPlayed(category, song);
    // Here and not in [scan], so a countdown that was closed again does not
    // cost the range one of its years. Saved with the game, or a resume would
    // start the range over.
    final year = currentYear;
    if (withoutCards && year != null && _playedYears.add(year)) _save();
    notifyListeners();

    final result = await _launch(_launcher, song);
    // The round can be gone by the time the launch answers: scores reset, a new
    // game, the song swapped. A song that started here after all must not run
    // on under whatever the screen shows now.
    if (!_isStillPlaying(song)) {
      if (result.inApp) unawaited(_stopMusic?.call());
      return;
    }
    launchMessage = result.message;
    playingInApp = result.inApp;
    if (!result.opened) {
      phase = RoundPhase.revealed;
      _launchedAt = null;
    }
    notifyListeners();
  }

  /// Hands the current song over again, by link.
  ///
  /// The way out on the web: a blocked popup reaches the app as a success, so
  /// the playing screen offers this as a button, where the tap counts as the
  /// user gesture the browser wants.
  Future<void> reopen() async {
    final song = currentSong;
    if (song == null || phase != RoundPhase.playing || _launching) return;
    final result = await _launch(_linkLauncher, song);
    if (!_isStillPlaying(song)) return;
    launchMessage = result.message;
    playingInApp = result.inApp;
    notifyListeners();
  }

  bool _isStillPlaying(Song song) =>
      !_disposed && phase == RoundPhase.playing && identical(currentSong, song);

  /// A launcher that throws is a launch that did not happen - never a round
  /// stuck halfway into playing.
  Future<LaunchResult> _launch(SongLauncher launcher, Song song) async {
    _launching = true;
    try {
      return await launcher.open(song);
    } on Object catch (error) {
      debugPrint('Launch failed: $error');
      return const LaunchResult(
        opened: false,
        message: 'The song would not start. Look it up by hand.',
      );
    } finally {
      _launching = false;
    }
  }

  /// The in-app player took the song and then could not play it after all -
  /// Spotify only says so after it has accepted the track.
  ///
  /// The round goes on as a link round: the "Open in Spotify" button comes
  /// back, and that is the way to the music now. It is not opened from here,
  /// because nobody tapped anything and a browser would block the tab.
  void playbackFailedInApp() {
    if (phase != RoundPhase.playing || !playingInApp) return;
    playingInApp = false;
    launchMessage = 'Spotify could not play the song here - open it there.';
    notifyListeners();
  }

  /// True when the year of the running round holds another song to swap in.
  bool get canRedraw {
    final year = currentYear;
    final song = currentSong;
    final category = currentCategory;
    if (phase != RoundPhase.playing ||
        year == null ||
        song == null ||
        category == null) {
      return false;
    }
    final current = _playedKey(category, song);
    return categories.any(
      (c) => songsFor(c, year).any((s) => _playedKey(c, s) != current),
    );
  }

  /// Swaps the song of the running round for another one of the same year.
  ///
  /// For the song nobody in the room knows: that round is a coin flip, which is
  /// exactly what the curation tries to keep out of the deck. The swapped song
  /// stays played, so it does not come back in this game either.
  ///
  /// Goes back to [RoundPhase.countdown], where a scan leads, so the new song
  /// is handed over the same way. False when the year holds nothing else.
  bool redraw() {
    final year = currentYear;
    final song = currentSong;
    final category = currentCategory;
    if (phase != RoundPhase.playing ||
        _launching ||
        year == null ||
        song == null ||
        category == null) {
      return false;
    }

    final draw = _draw(year, exclude: _playedKey(category, song));
    if (draw == null) return false;

    final skippedByIt = _skipped.add(song.key);
    if (skippedByIt) _onSkippedChanged?.call({..._skipped});
    _lastRedraw = (
      from: song,
      fromCategory: category,
      skippedByIt: skippedByIt,
      to: draw.song,
      toCategory: draw.category,
      toWasPlayed: _played.contains(_playedKey(draw.category, draw.song)),
    );

    currentSong = draw.song;
    currentCategory = draw.category;
    launchMessage = null;
    playingInApp = false;
    _launchedAt = null;
    phase = RoundPhase.countdown;
    notifyListeners();
    return true;
  }

  /// True while a launch is on its way and has not said yet whether the song
  /// plays in the tab.
  bool get launching => _launching;

  /// True while the running round's song came in by [redraw] and the one it
  /// replaced can still be brought back.
  bool get canUndoRedraw {
    final last = _lastRedraw;
    return last != null &&
        phase == RoundPhase.playing &&
        identical(currentSong, last.to);
  }

  /// Takes the last [redraw] back: the song that was swapped away is the
  /// round's song again, for a swap that was a slip or a room that knew it
  /// after all.
  ///
  /// The swap leaves no trace - the song loses its mark in [skipped], and the
  /// one it brought counts as unplayed again if it was before. Goes back to
  /// [RoundPhase.countdown] like [redraw], so the song is handed over again
  /// from the start. False when there is nothing to take back.
  bool undoRedraw() {
    final last = _lastRedraw;
    if (!canUndoRedraw || _launching || last == null) return false;

    if (last.skippedByIt && _skipped.remove(last.from.key)) {
      _onSkippedChanged?.call({..._skipped});
    }
    if (!last.toWasPlayed &&
        _played.remove(_playedKey(last.toCategory, last.to))) {
      _onPlayedChanged?.call({..._played});
    }
    _lastRedraw = null;

    currentSong = last.from;
    currentCategory = last.fromCategory;
    launchMessage = null;
    playingInApp = false;
    _launchedAt = null;
    phase = RoundPhase.countdown;
    notifyListeners();
    return true;
  }

  /// Coming back from Spotify: the year is revealed.
  void onAppResumed({DateTime? now}) {
    if (phase != RoundPhase.playing) return;
    // Nothing was handed over, so a `resumed` is somebody switching away and
    // back mid-guess - not the way back from Spotify, and no reason to spoil
    // the year. The button is the way out of an in-app round.
    //
    // While the launch is still out, which of the two it is is not known yet,
    // and a reveal cannot be taken back.
    if (playingInApp || _launching) return;
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
    playingInApp = false;
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
    final song = currentSong;
    final category = currentCategory;
    final year = currentYear;
    final over = winners.isNotEmpty;
    _finishingRound = over && song != null && category != null && year != null
        ? (song: song, category: category, year: year)
        : null;

    currentSong = null;
    currentCategory = null;
    currentYear = null;
    launchMessage = null;
    playingInApp = false;
    phase = over ? RoundPhase.finished : RoundPhase.idle;
    notifyListeners();
    // A finished game is nothing to resume; [undoFinish] saves it again.
    if (over) unawaited(_discard?.call());
  }

  /// True on the finish screen while the round that ended the game can still
  /// be taken back.
  bool get canUndoFinish =>
      phase == RoundPhase.finished && _finishingRound != null;

  /// Goes back to the reveal of the round that ended the game.
  ///
  /// The phone is passed around, and a double tap on a tile is all it takes to
  /// push somebody over the target. Without this that point could not be taken
  /// back: scores only change on the reveal, and the reveal was gone.
  void undoFinish() {
    final round = _finishingRound;
    if (phase != RoundPhase.finished || round == null) return;
    _finishingRound = null;
    currentSong = round.song;
    currentCategory = round.category;
    currentYear = round.year;
    phase = RoundPhase.revealed;
    notifyListeners();
    _save();
  }

  void resetScores() {
    for (final player in players) {
      player.score = 0;
    }
    // [_played] stays: the rematch is still the same room, and what it heard
    // a minute ago is the last thing it should hear again.
    _lastPlayedKey = null;
    _finishingRound = null;
    currentSong = null;
    currentCategory = null;
    currentYear = null;
    launchMessage = null;
    playingInApp = false;
    phase = RoundPhase.idle;
    notifyListeners();
    _save();
  }

  /// The songs of [category] for [year] that [service] can play.
  ///
  /// A song without the id of the service is swapped for another one of its
  /// year by simply not being in the pool. A year where none is left is a
  /// [ScanOutcome.noSongForYear], the same as a year the deck does not have.
  List<Song> songsFor(SongCategory category, int year) => [
    for (final song in category.songsForYear(year))
      if (song.playsOn(service)) song,
  ];

  /// Draws a song for that year: first a category at random, then one of its
  /// songs.
  ///
  /// The chance of a category is [weightOf] times its songs for the year,
  /// counted up to [_fullYear]: past that a well filled deck does not crowd
  /// out a thin one, below it a year of two songs does not take half the
  /// cards and play them to death. It does not depend on what has been
  /// played: a deck that has used up the year keeps its part and starts the
  /// year over, otherwise the one deck with something unplayed would take
  /// every card of that year. A deck without a song for the year drops out
  /// and the others share its part.
  ///
  /// Within the category the song is drawn by [_weightOf]: the core of a year
  /// comes up [_tierOneWeight] times as often as its long tail. In a game a
  /// year is usually scanned once or twice, so the tier decides which of its
  /// songs the room gets to hear at all.
  ///
  /// Played means played across games: nothing comes back while its year in
  /// its deck still holds a song this device has not played.
  ///
  /// Played is counted per deck, but a song played in another deck waits too
  /// while its deck has something played nowhere: Anthony and Anthony All
  /// share nearly every song, and picked together they would otherwise play
  /// it twice in an evening. That only changes the order - it never starts a
  /// year over or keeps a song out that its deck still needs.
  ///
  /// Once everything is used up the year starts over: a repeat beats a dead
  /// card. Over means over - the year's songs leave [_played], so it runs
  /// through all of them again before the next repeat instead of drawing with
  /// replacement from then on. Only the song it just ended on sits out.
  ///
  /// [exclude] is a played key that must not come out at all: the song
  /// [redraw] is swapping away.
  ({SongCategory category, Song song})? _draw(int year, {String? exclude}) {
    List<Song> poolOf(SongCategory category) => [
      for (final song in songsFor(category, year))
        if (_playedKey(category, song) != exclude) song,
    ];

    final candidates = [
      for (final category in categories)
        if (poolOf(category).isNotEmpty) category,
    ];
    if (candidates.isEmpty) return null;

    final category = _pickCategory({
      for (final category in candidates)
        category: weightOf(category) * min(poolOf(category).length, _fullYear),
    });
    final pool = poolOf(category);
    var songs = [
      for (final song in pool)
        if (!_played.contains(_playedKey(category, song))) song,
    ];
    if (songs.isEmpty) {
      for (final song in songsFor(category, year)) {
        _played.remove(_playedKey(category, song));
      }
      _onPlayedChanged?.call({..._played});
      songs = [
        for (final song in pool)
          if (_playedKey(category, song) != _lastPlayedKey) song,
      ];
      if (songs.isEmpty) songs = pool;
    }

    // After a start over, so the year's own songs no longer count.
    final playedAnywhere = {
      for (final key in _played) key.substring(key.indexOf('|') + 1),
    };
    final fresh = [
      for (final song in songs)
        if (!playedAnywhere.contains(song.key)) song,
    ];

    return (
      category: category,
      song: _pickWeighted(fresh.isEmpty ? songs : fresh),
    );
  }

  /// How many songs of a year count towards its deck's share: the size of a
  /// curated 2000+ year. A deck with more is still one deck.
  static const int _fullYear = 10;

  /// Picks one of the non-empty [shares]' keys, each as often as its value.
  SongCategory _pickCategory(Map<SongCategory, int> shares) {
    var total = 0;
    for (final share in shares.values) {
      total += share;
    }

    var roll = _random.nextInt(total);
    for (final MapEntry(key: category, value: share) in shares.entries) {
      roll -= share;
      if (roll < 0) return category;
    }
    return shares.keys.last;
  }

  /// How much more often a `tier: 1` song is drawn than a `tier: 2` one.
  static const int _tierOneWeight = 3;

  /// A swapped away song counts as tail whatever its tier, see [_skipped].
  int _weightOf(Song song) =>
      song.tier == 1 && !_skipped.contains(song.key) ? _tierOneWeight : 1;

  /// Picks from a non-empty list, each song weighted by [_weightOf].
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

  void _markPlayed(SongCategory category, Song song) {
    final key = _playedKey(category, song);
    _played.add(key);
    _lastPlayedKey = key;
    _onPlayedChanged?.call({..._played});
  }

  /// The same song can sit in two categories - it counts as played per deck.
  static String playedKey(SongCategory category, Song song) =>
      _playedKey(category, song);

  static String _playedKey(SongCategory category, Song song) =>
      '${category.id}|${song.key}';

  void _save() {
    final persist = _persist;
    if (persist == null) return;
    unawaited(persist(snapshot));
  }

  /// A launch can answer after the game screen is gone and the controller with
  /// it; that answer has nobody left to tell.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
