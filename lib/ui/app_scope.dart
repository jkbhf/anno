import 'package:flutter/widgets.dart';

import '../data/year_database.dart';
import '../models/song_category.dart';
import '../music/music_service.dart';
import '../music/spotify_session.dart';
import '../sync/tv_link.dart';

/// Passes the data loaded at startup down the tree.
class AppScope extends InheritedWidget {
  const AppScope({
    required this.years,
    required this.categories,
    required this.spotify,
    required this.link,
    required this.service,
    required super.child,
    this.onImport,
    this.onRemoveImported,
    super.key,
  });

  final YearDatabase years;
  final List<SongCategory> categories;

  /// The in-app player. Unavailable on everything but the web, and there only
  /// once a client id is compiled in and somebody has logged in.
  final SpotifySession spotify;

  /// The line to a second screen. Lives above every screen because it has to
  /// outlive all of them: pairing happens on the setup screen and the round
  /// it carries is on the game screen.
  final TvLink link;

  /// Where this device plays songs, switched on the setup screen and read when
  /// a game starts. A notifier rather than a value, so switching it does not
  /// rebuild the whole tree.
  final ValueNotifier<MusicService> service;

  /// Adds a deck read from a file to the ones on this device. Null where the
  /// app was not built with the import (tests).
  final Future<void> Function(SongCategory deck)? onImport;

  /// Takes an imported deck, by id, off the device again.
  final Future<void> Function(String id)? onRemoveImported;

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
      link != oldWidget.link ||
      service != oldWidget.service;
}
