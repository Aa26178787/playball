class User {
  final int id;
  final String email;
  final String nickname;
  final String? profileImage;

  User({
    required this.id,
    required this.email,
    required this.nickname,
    this.profileImage,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id:           json['id'],
      email:        json['email'] ?? '',
      nickname:     json['nickname'] ?? '',
      profileImage: json['profile_image'],
    );
  }
}