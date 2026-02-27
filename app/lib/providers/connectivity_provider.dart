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

  ConnectivityNotifier(String? baseUrl)
      : super(const ServerConnectivityState()) {
    if (baseUrl != null) {
      final serverUrl = baseUrl.replaceAll('/api/v1', '');
      _service.startMonitoring(serverUrl);
      _sub = _service.stream.listen((s) {
        state = s;
      });
    }
  }

  ConnectivityService get service => _service;

  Future<void> checkNow() async {
    await _service.checkNow();
  }

  Future<void> reconnect(String newServerUrl) async {
    await _service.reconnect(newServerUrl);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
