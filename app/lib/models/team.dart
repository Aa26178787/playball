class Team {
  final int id;
  final String name;
  final String shortName;
  final int? rank;
  final int wins;
  final int losses;
  final int draws;
  final double winRate;
  final double? gamesBehind;
  final String? logoUrl;

  Team({
    required this.id,
    required this.name,
    required this.shortName,
    this.rank,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.winRate,
    this.gamesBehind,
    this.logoUrl,
  });

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id:           json['id'],
      name:         json['name'] ?? '',
      shortName:    json['short_name'] ?? '',
      rank:         json['rank'],
      wins:         json['wins'] ?? 0,
      losses:       json['losses'] ?? 0,
      draws:        json['draws'] ?? 0,
      winRate:      (json['win_rate'] ?? 0).toDouble(),
      gamesBehind:  json['games_behind']?.toDouble(),
      logoUrl:      json['logo_url'],
    );
  }
}