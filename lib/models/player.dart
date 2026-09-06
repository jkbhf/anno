/// A player and their score.
class GamePlayer {
  GamePlayer({required this.name, this.score = 0});

  factory GamePlayer.fromJson(Map<String, dynamic> json) =>
      GamePlayer(name: json['name'] as String, score: json['score'] as int);

  final String name;
  int score;

  Map<String, dynamic> toJson() => {'name': name, 'score': score};
}
