import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/voice_chat_provider.dart';
import '../../providers/auth_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// TV tab - voice/text chat remote control for server TV display.
class TvTab extends ConsumerStatefulWidget {
  const TvTab({super.key});

  @override
  ConsumerState<TvTab> createState() => _TvTabState();
}

class _TvTabState extends ConsumerState<TvTab> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _stt = stt.SpeechToText();
  bool _sttAvailable = false;

  @override
  void initState() {
    super.initState();
    _initStt();
    Future.microtask(_connectWs);
  }

  Future<void> _initStt() async {
    _sttAvailable = await _stt.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _connectWs() async {
    final api = ref.read(apiClientProvider);
    final token = api.accessToken;
    final baseUrl = api.baseUrl;
    if (token != null && baseUrl != null) {
      // Strip /api/v1 suffix to get raw server URL
      final serverUrl = baseUrl.replaceAll('/api/v1', '');
      await ref.read(voiceChatProvider.notifier).connect(serverUrl, token);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _stt.stop();
    super.dispose();
  }

  void _send() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    ref.read(voiceChatProvider.notifier).sendTextCommand(text);
    _textController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startListening() {
    if (!_sttAvailable) return;
    ref.read(voiceChatProvider.notifier).setListening(true);
    _stt.listen(
      onResult: (result) {
        if (result.finalResult) {
          ref.read(voiceChatProvider.notifier).setListening(false);
          if (result.recognizedWords.isNotEmpty) {
            ref
                .read(voiceChatProvider.notifier)
                .sendTextCommand(result.recognizedWords);
            _scrollToBottom();
          }
        }
      },
      localeId: 'ko_KR',
    );
  }

  void _stopListening() {
    _stt.stop();
    ref.read(voiceChatProvider.notifier).setListening(false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceChatProvider);
    final theme = Theme.of(context);
    final api = ref.read(apiClientProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TV 리모콘'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              Icons.circle,
              size: 10,
              color: state.isConnected ? Colors.green : Colors.red,
            ),
          ),
          if (state.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () =>
                  ref.read(voiceChatProvider.notifier).clearMessages(),
            ),
        ],
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: state.messages.isEmpty
                ? _buildEmptyState(theme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: state.messages.length,
                    itemBuilder: (context, index) {
                      final msg = state.messages[index];
                      return _buildMessageBubble(msg, theme, api.baseUrl);
                    },
                  ),
          ),
          // Input area
          Container(
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              MediaQuery.of(context).padding.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: '명령을 입력하세요...',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _send,
                ),
                if (_sttAvailable)
                  IconButton(
                    icon: Icon(
                      state.isListening ? Icons.mic : Icons.mic_none,
                      color: state.isListening ? Colors.red : null,
                    ),
                    onPressed: state.isListening
                        ? _stopListening
                        : _startListening,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.tv, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'TV에 명령을 보내보세요',
            style: TextStyle(
              color: theme.colorScheme.outline,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _ExampleChip('"사진 보여줘"', onTap: () {
                ref
                    .read(voiceChatProvider.notifier)
                    .sendTextCommand('사진 보여줘');
                _scrollToBottom();
              }),
              _ExampleChip('"슬라이드쇼 틀어줘"', onTap: () {
                ref
                    .read(voiceChatProvider.notifier)
                    .sendTextCommand('슬라이드쇼 틀어줘');
                _scrollToBottom();
              }),
              _ExampleChip('"바다 사진 찾아줘"', onTap: () {
                ref
                    .read(voiceChatProvider.notifier)
                    .sendTextCommand('바다 사진 찾아줘');
                _scrollToBottom();
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
      ChatMessage msg, ThemeData theme, String? baseUrl) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: const Icon(Icons.tv, size: 18),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primary
                    : msg.type == 'error'
                        ? theme.colorScheme.errorContainer
                        : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.text,
                    style: TextStyle(
                      color: isUser
                          ? theme.colorScheme.onPrimary
                          : msg.type == 'error'
                              ? theme.colorScheme.onErrorContainer
                              : theme.colorScheme.onSurface,
                      fontSize: 14,
                    ),
                  ),
                  // Photo thumbnails for photo_grid responses
                  if (msg.photos != null && msg.photos!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount:
                            msg.photos!.length > 6 ? 6 : msg.photos!.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 4),
                        itemBuilder: (_, i) {
                          final photo = msg.photos![i];
                          final photoId = photo['id'] as String?;
                          if (photoId == null || baseUrl == null) {
                            return const SizedBox.shrink();
                          }
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl:
                                  '$baseUrl/photos/$photoId/thumb?size=small',
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                width: 80,
                                height: 80,
                                color: Colors.grey[300],
                                child: const Icon(Icons.image),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (msg.photos!.length > 6)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '+${msg.photos!.length - 6}장 더',
                          style: TextStyle(
                            color: theme.colorScheme.outline,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ExampleChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _ExampleChip(this.text, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(text),
      onPressed: onTap,
    );
  }
}
