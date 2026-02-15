import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/connectivity_service.dart';
import 'auth_provider.dart';

/// Provides server connectivity state.
final connectivityProvider = StateNotifierProvider<ConnectivityNotifier,
    ServerConnectivityState>((ref) {
  final api = ref.read(apiClientProvider);
  return ConnectivityNotifier(api.baseUrl);
});

class ConnectivityNotifier extends StateNotifier<ServerConnectivityState> {
  final ConnectivityService _service = ConnectivityService();
  StreamSubscription? _sub;
  bool _forceOffline = false;
  ServerConnectivityState _realState = const ServerConnectivityState();

  ConnectivityNotifier(String? baseUrl)
      : super(const ServerConnectivityState()) {
    if (baseUrl != null) {
      final serverUrl = baseUrl.replaceAll('/api/v1', '');
      _service.startMonitoring(serverUrl);
      _sub = _service.stream.listen((s) {
        _realState = s;
        _applyState();
      });
    }
  }

  ConnectivityService get service => _service;

  /// Whether force-offline debug mode is active.
  bool get isForceOffline => _forceOffline;

  /// Toggle force-offline mode for testing.
  void toggleForceOffline() {
    _forceOffline = !_forceOffline;
    _applyState();
  }

  void _applyState() {
    if (_forceOffline) {
      state = const ServerConnectivityState(
        isWiFi: false,
        isServerReachable: false,
      );
    } else {
      state = _realState;
    }
  }

  Future<void> checkNow() async {
    await _service.checkNow();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
