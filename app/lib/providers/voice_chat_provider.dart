import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ws_client.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final String? type; // command_result, tts, error, display_sync
  final List<Map<String, dynamic>>? photos;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.type,
    this.photos,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class VoiceChatState {
  final List<ChatMessage> messages;
  final bool isConnected;
  final bool isListening;

  const VoiceChatState({
    this.messages = const [],
    this.isConnected = false,
    this.isListening = false,
  });

  VoiceChatState copyWith({
    List<ChatMessage>? messages,
    bool? isConnected,
    bool? isListening,
  }) {
    return VoiceChatState(
      messages: messages ?? this.messages,
      isConnected: isConnected ?? this.isConnected,
      isListening: isListening ?? this.isListening,
    );
  }
}

class VoiceChatNotifier extends StateNotifier<VoiceChatState> {
  final WsClient _ws = WsClient();
  StreamSubscription? _sub;

  VoiceChatNotifier() : super(const VoiceChatState());

  Future<void> connect(String baseUrl, String token) async {
    await _ws.connect(baseUrl, token, endpoint: '/ws/voice');
    _sub = _ws.messages.listen(_onMessage);
    state = state.copyWith(isConnected: true);
  }

  void sendTextCommand(String text) {
    if (text.trim().isEmpty) return;
    // Add user message to chat
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(text: text.trim(), isUser: true),
      ],
    );
    // Send via WebSocket
    _ws.send({'type': 'text_command', 'text': text.trim()});
  }

  void setListening(bool value) {
    state = state.copyWith(isListening: value);
  }

  void _onMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;

    switch (type) {
      case 'command_result':
        final response = msg['response'] as String? ?? '';
        final screen = msg['screen'] as String?;
        List<Map<String, dynamic>>? photos;
        if (screen == 'photo_grid') {
          final photoList = msg['photos'] as List?;
          photos = photoList?.cast<Map<String, dynamic>>();
        }
        state = state.copyWith(
          messages: [
            ...state.messages,
            ChatMessage(
              text: response,
              isUser: false,
              type: screen ?? 'command_result',
              photos: photos,
            ),
          ],
        );
        break;

      case 'tts':
        final text = msg['text'] as String? ?? '';
        if (text.isNotEmpty) {
          state = state.copyWith(
            messages: [
              ...state.messages,
              ChatMessage(text: text, isUser: false, type: 'tts'),
            ],
          );
        }
        break;

      case 'error':
        final message = msg['message'] as String? ?? '오류가 발생했습니다';
        state = state.copyWith(
          messages: [
            ...state.messages,
            ChatMessage(text: message, isUser: false, type: 'error'),
          ],
        );
        break;

      case 'pong':
        break; // Ignore heartbeat responses
    }
  }

  void clearMessages() {
    state = state.copyWith(messages: []);
  }

  Future<void> disconnectVoice() async {
    _sub?.cancel();
    await _ws.disconnect();
    state = state.copyWith(isConnected: false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ws.dispose();
    super.dispose();
  }
}

final voiceChatProvider =
    StateNotifierProvider<VoiceChatNotifier, VoiceChatState>((ref) {
  return VoiceChatNotifier();
});
