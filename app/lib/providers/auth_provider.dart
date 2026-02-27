import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/auth.dart';
import '../models/server_info.dart';
import '../services/api_client.dart';

/// Global API client singleton.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Authentication state.
enum AuthState { initial, unauthenticated, pairing, authenticated }

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api;
  UserProfile? _profile;

  AuthNotifier(this._api) : super(AuthState.initial);

  UserProfile? get profile => _profile;

  /// Try restoring saved session.
  /// If stored credentials exist, immediately authenticate (no network call).
  /// Profile is loaded later asynchronously when server becomes reachable.
  Future<void> tryRestore() async {
    final ok = await _api.restoreSession();
    if (!ok) {
      state = AuthState.unauthenticated;
      return;
    }

    // Credentials exist → immediately go authenticated (offline-safe)
    state = AuthState.authenticated;

    // Load profile in background (fire-and-forget)
    _loadProfileAsync();
  }

  /// Load user profile asynchronously. Does not block app startup.
  Future<void> _loadProfileAsync() async {
    try {
      final resp = await _api.get('/users/me');
      _profile = UserProfile.fromJson(resp.data);
    } catch (_) {
      // Server unreachable → offline mode, profile stays null
    }
  }

  /// Start pairing with a discovered server.
  Future<Map<String, dynamic>> initPairing(ServerInfo server) async {
    await _api.configure(baseUrl: server.baseUrl);
    final resp = await _api.post('/pair/init');
    state = AuthState.pairing;
    return resp.data;
  }

  /// Submit PIN to complete pairing.
  Future<AuthTokens> submitPin({
    required String pin,
    required String deviceName,
    required String deviceType,
    String? deviceModel,
  }) async {
    final resp = await _api.post('/pair', data: {
      'pin': pin,
      'device_name': deviceName,
      'device_type': deviceType,
      if (deviceModel != null) 'device_model': deviceModel,
    });

    final tokens = AuthTokens.fromJson(resp.data);
    await _api.configure(
      baseUrl: _api.baseUrl!.replaceAll('/api/v1', ''),
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      deviceId: tokens.deviceId,
    );
    return tokens;
  }

  /// Complete user setup (nickname + password).
  Future<void> setupUser(String nickname, String password) async {
    await _api.post('/users/setup', data: {
      'nickname': nickname,
      'password': password,
    });
    final resp = await _api.get('/users/me');
    _profile = UserProfile.fromJson(resp.data);
    state = AuthState.authenticated;
  }

  /// Logout.
  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {}
    await _api.clearSession();
    _profile = null;
    state = AuthState.unauthenticated;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(apiClientProvider));
});
