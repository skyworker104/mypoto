import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket client for real-time communication with server.
class WsClient {
  WebSocketChannel? _channel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _heartbeatTimer;
  String? _url;
  String? _token;
  String _endpoint = '/ws';

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  bool get isConnected => _channel != null;

  Future<void> connect(String baseUrl, String token, {String endpoint = '/ws'}) async {
    _url = baseUrl.replaceFirst('http', 'ws');
    _token = token;
    _endpoint = endpoint;

    final uri = Uri.parse('$_url$_endpoint?token=$token');
    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      (data) {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          _messageController.add(msg);
        } catch (_) {}
      },
      onDone: _onDisconnected,
      onError: (_) => _onDisconnected(),
    );

    _startHeartbeat();
  }

  void send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => send({'type': 'ping'}),
    );
  }

  void _onDisconnected() {
    _heartbeatTimer?.cancel();
    _channel = null;
    // Auto-reconnect after 3 seconds
    if (_url != null && _token != null) {
      Future.delayed(const Duration(seconds: 3), () {
        if (_channel == null) connect(_url!, _token!, endpoint: _endpoint);
      });
    }
  }

  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _url = null;
    _token = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _messageController.close();
  }
}
