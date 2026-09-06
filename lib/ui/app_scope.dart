import 'package:flutter/widgets.dart';

import '../data/year_database.dart';
import '../models/song_category.dart';
import '../music/spotify_session.dart';

/// Passes the data loaded at startup down the tree.
class AppScope extends InheritedWidget {
  const AppScope({
    required this.years,
    required this.categories,
    required this.spotify,
    required super.child,
    super.key,
  });

  final YearDatabase years;
  final List<SongCategory> categories;

  /// The in-app player. Unavailable on everything but the web, and there only
  /// once a client id is compiled in and somebody has logged in.
  final SpotifySession spotify;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      years != oldWidget.years ||
      categories != oldWidget.categories ||
      spotify != oldWidget.spotify;
}
