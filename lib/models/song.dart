/// A song from a category's catalog.
///
/// [year] is the curated truth of the game and deliberately does NOT come from
/// a streaming API: those report the year of the re-release for remasters and
/// reissues instead of the original release.
///
/// For a contest category it is the year of the contest, not of the release -
/// a Eurovision entry from May 2005 that came out in December 2004 belongs on
/// the 2005 card, because that is the year the room is guessing.
class Song {
  const Song({
    required this.title,
    required this.artist,
    required this.year,
    this.spotifyTrackId,
    this.country,
    this.place,
    this.tier = 1,
  });

  /// Reads one entry from `assets/songs/<category>.json`.
  ///
  /// Throws [FormatException] so a typo in the catalog surfaces at startup
  /// instead of in the middle of a game.
  factory Song.fromJson(Map<String, dynamic> json) {
    final year = json['year'];
    final title = json['title'];
    final artist = json['artist'];
    if (year is! int || title is! String || artist is! String) {
      throw FormatException('Song needs year (int), title and artist: $json');
    }
    final trackId = json['spotifyTrackId'];
    if (trackId != null && trackId is! String) {
      throw FormatException('spotifyTrackId must be a string: $json');
    }
    final id = trackId as String?;

    final country = json['country'];
    if (country != null && country is! String) {
      throw FormatException('country must be a string: $json');
    }
    final place = json['place'];
    if (place != null && (place is! int || place < 1)) {
      throw FormatException('place must be a positive int: $json');
    }
    final tier = json['tier'];
    if (tier != null && (tier is! int || (tier != 1 && tier != 2))) {
      throw FormatException('tier must be 1 or 2: $json');
    }

    return Song(
      title: title,
      artist: artist,
      year: year,
      spotifyTrackId: (id == null || id.isEmpty) ? null : id,
      country: country as String?,
      place: place as int?,
      tier: (tier as int?) ?? 1,
    );
  }

  final String title;
  final String artist;
  final int year;

  /// The 22 character Spotify track id, the last part of
  /// `https://open.spotify.com/track/<id>`.
  ///
  /// Without it the app opens a Spotify search for title and artist instead -
  /// playable, but the song has to be tapped there.
  final String? spotifyTrackId;

  /// Where the entry competed, for contest categories. Null everywhere else.
  final String? country;

  /// The rank it finished in, for contest categories.
  final int? place;

  /// How often the song is drawn against the others of its year: `1` is the
  /// core of the year and comes up more often, `2` its long tail.
  ///
  /// Defaults to 1, which is what every song of a thin year gets - the tiers
  /// only pull apart where a year holds more than a handful. `CLAUDE.md` has
  /// the rule for which entry belongs in which tier.
  final int tier;

  /// True when the song carries the extra facts of a contest entry.
  bool get isContestEntry => country != null || place != null;

  /// [place] as an English ordinal: 1 -> `1st`, 12 -> `12th`, 23 -> `23rd`.
  String? get placeOrdinal {
    final rank = place;
    if (rank == null) return null;
    final suffix = switch ((rank % 100, rank % 10)) {
      (11 || 12 || 13, _) => 'th',
      (_, 1) => 'st',
      (_, 2) => 'nd',
      (_, 3) => 'rd',
      _ => 'th',
    };
    return '$rank$suffix';
  }

  /// Stable key within a category, used to avoid repeats in a game.
  String get key => spotifyTrackId ?? '$year|$title|$artist';

  @override
  String toString() => '$title - $artist ($year)';
}
