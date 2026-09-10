import 'song.dart';

/// A deck of songs a game is played from.
class SongCategory {
  SongCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.songs,
    this.needsCompanion = false,
  }) : _byYear = <int, List<Song>>{} {
    for (final song in songs) {
      _byYear.putIfAbsent(song.year, () => <Song>[]).add(song);
    }
  }

  factory SongCategory.fromJson(Map<String, dynamic> json) {
    final rawSongs = json['songs'];
    if (rawSongs is! List) {
      throw FormatException('Category needs a songs list: ${json['id']}');
    }
    final companion = json['needsCompanion'] ?? false;
    if (companion is! bool) {
      throw FormatException(
        'needsCompanion must be true or false: ${json['id']}',
      );
    }
    return SongCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      needsCompanion: companion,
      songs: [
        for (final entry in rawSongs)
          Song.fromJson(entry as Map<String, dynamic>),
      ],
    );
  }

  final String id;
  final String name;
  final String description;
  final List<Song> songs;

  /// True when the deck covers too few years to be played on its own.
  ///
  /// The cards run over the whole century, so a deck that only holds a decade
  /// answers most of them with nothing - a round without a song. Next to a
  /// full deck that never happens: `GameController` draws only among the
  /// categories that have a song for the scanned year, so the other one steps
  /// in and this deck simply waits for a year it can serve.
  ///
  /// Hence it is not a preference but a rule of the selection screen - see
  /// [canCarryGame]. `CLAUDE.md` holds when a deck earns the flag.
  final bool needsCompanion;

  final Map<int, List<Song>> _byYear;

  bool get isEmpty => songs.isEmpty;

  /// The years the deck spans, as "1950-2026" - or a single year where first
  /// and last are the same. Null while the deck is empty. A count of years
  /// would be the wrong number to show: the decks have no gaps, so it only
  /// restates the span while hiding where the deck actually sits in time.
  String? get yearSpan {
    if (_byYear.isEmpty) return null;
    final years = _byYear.keys.toList()..sort();
    final first = years.first;
    final last = years.last;
    return first == last ? '$first' : '$first-$last';
  }

  List<Song> songsForYear(int year) => _byYear[year] ?? const <Song>[];
}

/// Whether [selection] can be played as it stands.
///
/// One deck has to be able to answer any card, so a selection needs at least
/// one that is filled and does not carry [SongCategory.needsCompanion]. A
/// companion deck may join anything, it just cannot be the whole game.
bool canCarryGame(Iterable<SongCategory> selection) =>
    selection.any((c) => !c.isEmpty && !c.needsCompanion);
