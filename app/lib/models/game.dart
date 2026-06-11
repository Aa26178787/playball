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
  final String? winPitcherImage;
  final String? losePitcherImage;
  final bool? isDraw;
  final String? homeStarter;
  final String? awayStarter;
  final bool hasRoster; // preview 풀 로스터(후보/불펜) 적재 여부 — '로스터 확정' 단계
  final Map<String, dynamic>? weather;
  final List<String> homeRecent5;
  final List<String> awayRecent5;
  final int? homeTeamId;
  final int? awayTeamId;
  final int? stadiumId;

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
    this.winPitcherImage,
    this.losePitcherImage,
    this.isDraw,
    this.homeStarter,
    this.awayStarter,
    this.hasRoster = false,
    this.weather,
    this.homeRecent5 = const [],
    this.awayRecent5 = const [],
    this.homeTeamId,
    this.awayTeamId,
    this.stadiumId,
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
      winPitcher:       json['win_pitcher'],
      losePitcher:      json['lose_pitcher'],
      winPitcherImage:  json['win_pitcher_image'],
      losePitcherImage: json['lose_pitcher_image'],
      isDraw:           json['is_draw'] == true,
      homeStarter:   json['home_starter'],
      awayStarter:   json['away_starter'],
      hasRoster:     json['has_roster'] == true,
      weather:       json['weather'] != null
                       ? Map<String, dynamic>.from(json['weather'])
                       : null,
      homeRecent5:   List<String>.from(json['home_recent_5'] ?? []),
      awayRecent5:   List<String>.from(json['away_recent_5'] ?? []),
      homeTeamId:    json['home_team_id'],
      awayTeamId:    json['away_team_id'],
      stadiumId:     json['stadium_id'],
    );
  }
}