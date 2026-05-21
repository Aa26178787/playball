class Game {
  final int id;
  final String gameDate;
  final String status;
  final int homeScore;
  final int awayScore;
  final int? currentInning;
  final String? inningHalf;
  final String homeTeam;
  final String homeTeamCode;
  final String awayTeam;
  final String awayTeamCode;
  final String? stadium;
  final String? startTime;
  final String? winPitcher;
  final String? losePitcher;
  final bool? isDraw;
  final String? homeStarter;
  final String? awayStarter;
  final Map<String, dynamic>? weather;

  Game({
    required this.id,
    required this.gameDate,
    required this.status,
    required this.homeScore,
    required this.awayScore,
    this.currentInning,
    this.inningHalf,
    required this.homeTeam,
    required this.homeTeamCode,
    required this.awayTeam,
    required this.awayTeamCode,
    this.stadium,
    this.startTime,
    this.winPitcher,
    this.losePitcher,
    this.isDraw,
    this.homeStarter,
    this.awayStarter,
    this.weather,
  });

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id:            json['id'],
      gameDate:      json['game_date'] ?? '',
      status:        json['status'] ?? '예정',
      homeScore:     json['home_score'] ?? 0,
      awayScore:     json['away_score'] ?? 0,
      currentInning: json['current_inning'],
      inningHalf:    json['inning_half'],
      homeTeam:      json['home_team'] ?? '',
      homeTeamCode:  json['home_team_code'] ?? '',
      awayTeam:      json['away_team'] ?? '',
      awayTeamCode:  json['away_team_code'] ?? '',
      stadium:       json['stadium'],
      startTime:     json['start_time'],
      winPitcher:    json['win_pitcher'],
      losePitcher:   json['lose_pitcher'],
      isDraw:        json['is_draw'] == true,
      homeStarter:   json['home_starter'],
      awayStarter:   json['away_starter'],
      weather:       json['weather'] != null
                       ? Map<String, dynamic>.from(json['weather'])
                       : null,
    );
  }
}