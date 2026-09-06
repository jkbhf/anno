import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Result of a JSON import.
class ImportResult {
  const ImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
  });

  final int added;
  final int updated;
  final int skipped;

  int get total => added + updated;
}

/// The mapping of QR code to year.
///
/// Two layers: `assets/qr_years.json` ships with the app, the years entered on
/// the device live in SharedPreferences and take precedence. That keeps the
/// bundled file untouched, so "delete own entries" always leads back to a
/// defined state.
class YearDatabase extends ChangeNotifier {
  YearDatabase._(this._defaults, this._local, this._prefs);

  static const String _prefsKey = 'year_db.local';
  static const String defaultAsset = 'assets/qr_years.json';

  final Map<String, int> _defaults;
  final Map<String, int> _local;
  final SharedPreferences? _prefs;

  /// For tests: a database without assets and without persistence.
  @visibleForTesting
  factory YearDatabase.inMemory({
    Map<String, int> defaults = const {},
    Map<String, int> local = const {},
  }) => YearDatabase._({...defaults}, {...local}, null);

  static Future<YearDatabase> load({AssetBundle? bundle}) async {
    final source = bundle ?? rootBundle;
    Map<String, int> defaults = {};
    try {
      defaults = _parse(await source.loadString(defaultAsset)).entries;
    } on Exception catch (error) {
      debugPrint('qr_years.json not readable: $error');
    }

    SharedPreferences? prefs;
    Map<String, int> local = {};
    try {
      prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      if (stored != null) local = _parse(stored).entries;
    } on Exception catch (error) {
      debugPrint('Local year database not readable: $error');
    }

    return YearDatabase._(defaults, local, prefs);
  }

  /// The key of a scanned code.
  ///
  /// The cards carry links of the form
  /// `https://play-the-music.com/de/year/182ca01194a98f0b`; what matters is the
  /// last path segment. Anything else - a bare year included - becomes the key
  /// as a whole.
  static String normalizeKey(String raw) {
    var value = raw.trim();
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) value = segments.last;
    }
    return value.toLowerCase();
  }

  /// The year for a scanned code, or null when it is unknown.
  ///
  /// If the code itself holds a plausible year, that counts even without an
  /// entry in the database - handy for self-printed cards.
  int? yearFor(String raw) {
    final key = normalizeKey(raw);
    final known = _local[key] ?? _defaults[key];
    if (known != null) return known;
    final asYear = int.tryParse(key);
    if (asYear != null && isPlausibleYear(asYear)) return asYear;
    return null;
  }

  static bool isPlausibleYear(int year) => year >= 1900 && year <= 2100;

  /// Every known entry, own ones overriding the bundled file.
  Map<String, int> get entries => {..._defaults, ..._local};

  int get localCount => _local.length;
  int get defaultCount => _defaults.length;

  bool isLocal(String key) => _local.containsKey(key);

  Future<void> setYear(String raw, int year) async {
    _local[normalizeKey(raw)] = year;
    notifyListeners();
    await _persist();
  }

  /// Removes one own entry. A bundled value becomes visible again.
  Future<void> removeLocal(String key) async {
    if (_local.remove(key) == null) return;
    notifyListeners();
    await _persist();
  }

  Future<void> clearLocal() async {
    if (_local.isEmpty) return;
    _local.clear();
    notifyListeners();
    await _persist();
  }

  /// The full state as JSON - what the export puts on the clipboard and what
  /// [importJson] reads back in.
  String exportJson() {
    final all = entries;
    final sorted = all.keys.toList()..sort();
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'years': {for (final key in sorted) key: all[key]},
    });
  }

  /// Reads JSON from the clipboard and stores everything as own entries.
  /// Accepts the export format and a flat `{"code": year}` map.
  Future<ImportResult> importJson(String text) async {
    final parsed = _parse(text);
    var added = 0;
    var updated = 0;
    for (final entry in parsed.entries.entries) {
      final existing = _local[entry.key] ?? _defaults[entry.key];
      if (existing == null) {
        added++;
      } else if (existing != entry.value) {
        updated++;
      }
      _local[entry.key] = entry.value;
    }
    notifyListeners();
    await _persist();
    return ImportResult(
      added: added,
      updated: updated,
      skipped: parsed.skipped,
    );
  }

  Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(_prefsKey, jsonEncode(_local));
  }

  static _Parsed _parse(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('Expected a JSON object.');
    }
    final raw = decoded['years'] ?? decoded;
    if (raw is! Map) {
      throw const FormatException('Field "years" is not a JSON object.');
    }

    final years = <String, int>{};
    var skipped = 0;
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String || key.startsWith('_')) {
        skipped++;
        continue;
      }
      final value = entry.value;
      final year = value is int ? value : int.tryParse('$value');
      if (year == null || !isPlausibleYear(year)) {
        skipped++;
        continue;
      }
      years[normalizeKey(key)] = year;
    }
    if (years.isEmpty && skipped == 0) {
      throw const FormatException('No entries found.');
    }
    return _Parsed(years, skipped);
  }
}

class _Parsed {
  const _Parsed(this.entries, this.skipped);

  final Map<String, int> entries;
  final int skipped;
}
