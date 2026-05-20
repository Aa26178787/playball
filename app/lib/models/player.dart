class Player {
  final int id;
  final String name;
  final String? position;
  final int? number;
  final String? profileImage;
  final String? team;
  final String? playerType;
  final String? birthDate;
  final int? height;
  final int? weight;

  Player({
    required this.id,
    required this.name,
    this.position,
    this.number,
    this.profileImage,
    this.team,
    this.playerType,
    this.birthDate,
    this.height,
    this.weight,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id:           json['id'],
      name:         json['name'] ?? '',
      position:     json['position'],
      number:       json['number'],
      profileImage: json['profile_image'],
      team:         json['team'],
      playerType:   json['player_type'],
      birthDate:    json['birth_date'],
      height:       json['height'],
      weight:       json['weight'],
    );
  }
}