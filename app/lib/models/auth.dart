/// Authentication tokens and user session data.
class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final String deviceId;
  final String userId;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.deviceId,
    required this.userId,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      deviceId: json['device_id'] as String,
      userId: json['user_id'] as String,
    );
  }
}

class UserProfile {
  final String id;
  final String nickname;
  final String role;
  final String? avatarUrl;
  final String familyId;
  final String familyName;

  const UserProfile({
    required this.id,
    required this.nickname,
    required this.role,
    this.avatarUrl,
    required this.familyId,
    required this.familyName,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      nickname: json['nickname'] as String,
      role: json['role'] as String,
      avatarUrl: json['avatar_url'] as String?,
      familyId: json['family_id'] as String,
      familyName: json['family_name'] as String,
    );
  }
}
