import 'song.dart';

/// A deck of songs a game is played from.
class SongCategory {
  SongCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.songs,
    this.imported = false,
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
    return SongCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      imported: json['imported'] == true,
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

  /// A deck the player brought in from a file, kept on this device only.
  final bool imported;

  final Map<int, List<Song>> _byYear;

  bool get isEmpty => songs.isEmpty;

  /// The years the deck spans, as "1950-2026" - or a single year where first
  /// and last are the same. Null while the deck is empty. A count of years
  /// would be the wrong number to show: the decks have no gaps, so it only
  /// restates the span while hiding where the deck actually sits in time.
  String? get yearSpan {
    final first = firstYear;
    final last = lastYear;
    if (first == null || last == null) return null;
    return first == last ? '$first' : '$first-$last';
  }

  /// The ends of the span, null while the deck is empty. The game without
  /// cards picks its years out of these, see `GameController.nextYear`.
  int? get firstYear =>
      _byYear.isEmpty ? null : _byYear.keys.reduce((a, b) => a < b ? a : b);

  int? get lastYear =>
      _byYear.isEmpty ? null : _byYear.keys.reduce((a, b) => a > b ? a : b);

  List<Song> songsForYear(int year) => _byYear[year] ?? const <Song>[];
}

/// Whether [selection] can be played as it stands: at least one deck with
/// songs in it.
///
/// A deck that covers only part of the century - K-Pop from 2016 on - carries
/// a game on its own too. Its span stands on the selection card, so the room
/// plays the cards of those years, and a card outside it only brings up a
/// note, never a round without a song.
bool canCarryGame(Iterable<SongCategory> selection) =>
    selection.any((c) => !c.isEmpty);
