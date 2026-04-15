class UserModel {
  final String id;
  final String username;
  final String role;
  final String token;
  final String expiresAt;

  const UserModel({
    required this.id,
    required this.username,
    required this.role,
    required this.token,
    required this.expiresAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    return UserModel(
      id: (user['id'] ?? json['adminId'] ?? '').toString(),
      username: (user['username'] ?? json['adminUsername'] ?? '').toString(),
      role: (user['role'] ?? 'admin').toString(),
      token: (json['token'] ?? '').toString(),
      expiresAt: (json['expiresAt'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'role': role,
        'token': token,
        'expiresAt': expiresAt,
      };
}
