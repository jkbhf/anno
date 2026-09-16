import 'package:flutter/widgets.dart';

import '../data/year_database.dart';
import '../models/song_category.dart';
import '../music/music_service.dart';
import '../music/spotify_session.dart';

/// Passes the data loaded at startup down the tree.
class AppScope extends InheritedWidget {
  const AppScope({
    required this.years,
    required this.categories,
    required this.spotify,
    required this.service,
    required super.child,
    super.key,
  });

  final YearDatabase years;
  final List<SongCategory> categories;

  /// The in-app player. Unavailable on everything but the web, and there only
  /// once a client id is compiled in and somebody has logged in.
  final SpotifySession spotify;

  /// Where this device plays songs, switched on the setup screen and read when
  /// a game starts. A notifier rather than a value, so switching it does not
  /// rebuild the whole tree.
  final ValueNotifier<MusicService> service;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      years != oldWidget.years ||
      categories != oldWidget.categories ||
      spotify != oldWidget.spotify ||
      service != oldWidget.service;
}
