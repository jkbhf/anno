import 'song.dart';

/// A deck of songs a game is played from.
class SongCategory {
  SongCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.songs,
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

  final Map<int, List<Song>> _byYear;

  bool get isEmpty => songs.isEmpty;

  /// How many years have at least one song.
  int get coveredYears => _byYear.length;

  List<Song> songsForYear(int year) => _byYear[year] ?? const <Song>[];
}
