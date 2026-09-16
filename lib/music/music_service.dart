/// Where the songs of a round are played.
///
/// A setting of the device, not of the game: it follows who owns the phone
/// that is being passed around, and that does not change between two games of
/// the same evening.
enum MusicService {
  spotify('Spotify'),
  youtubeMusic('YouTube Music');

  const MusicService(this.label);

  /// The name the round screen shows: "Open in YouTube Music".
  final String label;

  /// The stored name back to a service. Spotify for anything unknown - it is
  /// what the app did before there was a choice.
  static MusicService fromName(String? name) => values.firstWhere(
    (service) => service.name == name,
    orElse: () => spotify,
  );
}
