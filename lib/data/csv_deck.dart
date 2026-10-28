import '../models/song.dart';
import '../models/song_category.dart';

/// Reads a Spotify playlist export (`Track URI`, `Track Name`,
/// `Artist Name(s)`, `Release Date` ...) into a deck, taking every row as it
/// stands - no year is corrected, no pressing checked.
class CsvDeck {
  /// The deck, or a [FormatException] where the file is not that format or
  /// holds no row with a usable year.
  static SongCategory parse(String text, {required String name}) {
    final rows = _rows(text);
    if (rows.isEmpty) throw const FormatException('The file is empty.');
    final header = [for (final h in rows.first) h.trim().toLowerCase()];
    int column(String title) => header.indexOf(title);
    final uri = column('track uri');
    final title = column('track name');
    final artist = column('artist name(s)');
    final date = column('release date');
    if (title < 0 || artist < 0 || date < 0) {
      throw const FormatException(
        'Not a playlist export: Track Name, Artist Name(s) and Release Date '
        'are needed.',
      );
    }

    final songs = <Song>[];
    for (final row in rows.skip(1)) {
      String cell(int i) => i >= 0 && i < row.length ? row[i].trim() : '';
      final year = int.tryParse(
        RegExp(r'^\d{4}').firstMatch(cell(date))?.group(0) ?? '',
      );
      if (year == null || cell(title).isEmpty) continue;
      final id = RegExp(r'^spotify:track:(\w{22})$').firstMatch(cell(uri));
      songs.add(
        Song(
          title: cell(title),
          artist: cell(artist).replaceAll(';', ', '),
          year: year,
          spotifyTrackId: id?.group(1),
        ),
      );
    }
    if (songs.isEmpty) throw const FormatException('No song with a year.');

    return SongCategory(
      id: 'import_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}',
      name: name,
      description: 'Imported playlist',
      songs: songs,
      imported: true,
    );
  }

  /// "Daily_Chill (1).csv" -> "Daily Chill".
  static String nameOf(String fileName) {
    var base = fileName.replaceAll(RegExp(r'\.csv$', caseSensitive: false), '');
    base = base.replaceAll(RegExp(r'\s*\(\d+\)$'), '');
    base = base.replaceAll(RegExp(r'[_\s]+'), ' ').trim();
    if (base.isEmpty) return 'Imported';
    return base
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// RFC 4180: quoted fields, doubled quotes, line breaks inside quotes.
  static List<List<String>> _rows(String text) {
    if (text.startsWith('﻿')) text = text.substring(1);
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      if (row.length > 1 || row.first.isNotEmpty) rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == ',') {
        endField();
      } else if (c == '\n') {
        endRow();
      } else if (c != '\r') {
        field.write(c);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }
}
