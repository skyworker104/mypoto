import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

/// Connectivity state for server reachability.
class ServerConnectivityState {
  final bool isWiFi;
  final bool isServerReachable;
  final bool isSameNetwork;

  const ServerConnectivityState({
    this.isWiFi = false,
    this.isServerReachable = false,
    this.isSameNetwork = true,
  });

  ServerConnectivityState copyWith({
    bool? isWiFi,
    bool? isServerReachable,
    bool? isSameNetwork,
  }) {
    return ServerConnectivityState(
      isWiFi: isWiFi ?? this.isWiFi,
      isServerReachable: isServerReachable ?? this.isServerReachable,
      isSameNetwork: isSameNetwork ?? this.isSameNetwork,
    );
  }
}

/// Monitors WiFi connectivity and server reachability.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final _controller = StreamController<ServerConnectivityState>.broadcast();
  final _storage = const FlutterSecureStorage();
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  String? _serverBaseUrl;
  ServerConnectivityState _state = const ServerConnectivityState();

  Stream<ServerConnectivityState> get stream => _controller.stream;
  ServerConnectivityState get state => _state;

  /// Start monitoring connectivity.
  void startMonitoring(String serverBaseUrl) {
    _serverBaseUrl = serverBaseUrl;
    _subscription = _connectivity.onConnectivityChanged.listen(_onChanged);
    // Check immediately
    _checkConnectivity();
    // Periodic server ping every 30 seconds
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkServer();
    });
  }

  Future<void> _onChanged(List<ConnectivityResult> results) async {
    await _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    final isWiFi = results.contains(ConnectivityResult.wifi);
    _state = _state.copyWith(isWiFi: isWiFi);

    if (isWiFi || results.contains(ConnectivityResult.ethernet)) {
      await _checkServer();
    } else {
      // Not on WiFi - don't try to connect to server
      _state = _state.copyWith(
        isServerReachable: false,
        isSameNetwork: false,
      );
      _controller.add(_state);
    }
  }

  Future<void> _checkServer() async {
    if (_serverBaseUrl == null) return;
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
      ));
      final resp = await dio.get(
        '$_serverBaseUrl${AppConfig.apiPrefix}/system/ping',
      );
      final reachable = resp.statusCode == 200;
      _state = _state.copyWith(
        isServerReachable: reachable,
        isSameNetwork: reachable,
      );
      // Save successful connection state
      if (reachable) {
        await _storage.write(
            key: 'last_server_url', value: _serverBaseUrl);
      }
    } catch (_) {
      _state = _state.copyWith(
        isServerReachable: false,
        isSameNetwork: false,
      );
    }
    _controller.add(_state);
  }

  /// Force a connectivity check now.
  Future<void> checkNow() async {
    await _checkConnectivity();
  }

  /// Reconnect to a new server URL.
  Future<void> reconnect(String newServerUrl) async {
    _serverBaseUrl = newServerUrl;
    await _checkServer();
  }

  void dispose() {
    _subscription?.cancel();
    _pingTimer?.cancel();
    _controller.close();
  }
}
