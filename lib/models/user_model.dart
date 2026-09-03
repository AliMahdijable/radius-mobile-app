class UserModel {
  final String id;
  final String username;
  final String role;
  final String token;
  final String expiresAt;
  final List<String> permissions;
  final bool canAccessManagers;
  final bool canAccessPackages;

  const UserModel({
    required this.id,
    required this.username,
    required this.role,
    required this.token,
    required this.expiresAt,
    this.permissions = const [],
    this.canAccessManagers = false,
    this.canAccessPackages = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    final rawPermissions = (json['permissions'] as List?) ??
        (user['permissions'] as List?) ??
        const [];
    return UserModel(
      id: (user['id'] ?? json['adminId'] ?? '').toString(),
      username: (user['username'] ?? json['adminUsername'] ?? '').toString(),
      role: (user['role'] ?? 'admin').toString(),
      token: (json['token'] ?? '').toString(),
      expiresAt: (json['expiresAt'] ?? '').toString(),
      permissions: rawPermissions.map((e) => e.toString()).toList(),
      canAccessManagers:
          (json['canAccessManagers'] ?? user['canAccessManagers']) == true,
      canAccessPackages:
          (json['canAccessPackages'] ?? user['canAccessPackages']) == true,
    );
  }

  UserModel copyWith({
    String? id,
    String? username,
    String? role,
    String? token,
    String? expiresAt,
    List<String>? permissions,
    bool? canAccessManagers,
    bool? canAccessPackages,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      role: role ?? this.role,
      token: token ?? this.token,
      expiresAt: expiresAt ?? this.expiresAt,
      permissions: permissions ?? this.permissions,
      canAccessManagers: canAccessManagers ?? this.canAccessManagers,
      canAccessPackages: canAccessPackages ?? this.canAccessPackages,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'role': role,
        'token': token,
        'expiresAt': expiresAt,
        'permissions': permissions,
        'canAccessManagers': canAccessManagers,
        'canAccessPackages': canAccessPackages,
      };
}
