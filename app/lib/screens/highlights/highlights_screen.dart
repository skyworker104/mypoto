import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/highlight_provider.dart';
import '../../providers/auth_provider.dart';

/// Highlights list screen showing generated highlight videos.
class HighlightsScreen extends ConsumerWidget {
  const HighlightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlightsAsync = ref.watch(highlightsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('하이라이트')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showGenerateDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: highlightsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('로딩 실패: $e')),
        data: (highlights) {
          if (highlights.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.movie_creation_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('하이라이트 영상이 없습니다',
                      style: TextStyle(color: Colors.grey)),
                  Text('+ 버튼으로 새 하이라이트를 만들어보세요',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: highlights.length,
            itemBuilder: (context, index) {
              final h = highlights[index];
              return _HighlightCard(highlight: h);
            },
          );
        },
      ),
    );
  }

  void _showGenerateDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('새 하이라이트'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: '제목',
                hintText: '예: 2025년 가족여행',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              final title = titleController.text.trim();
              if (title.isEmpty) return;
              final api = ref.read(apiClientProvider);
              await api.post('/highlights/generate', data: {
                'title': title,
                'source_type': 'date_range',
              });
              if (ctx.mounted) Navigator.pop(ctx);
              ref.invalidate(highlightsProvider);
            },
            child: const Text('생성'),
          ),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  final HighlightItem highlight;

  const _HighlightCard({required this.highlight});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          if (highlight.thumbnailUrl != null)
            SizedBox(
              height: 180,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: highlight.thumbnailUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: Colors.grey[200]),
                    errorWidget: (_, __, ___) =>
                        Container(color: Colors.grey[300]),
                  ),
                  if (highlight.hasVideo)
                    const Center(
                      child: Icon(Icons.play_circle_filled,
                          size: 56, color: Colors.white70),
                    ),
                ],
              ),
            )
          else
            Container(
              height: 120,
              color: Colors.grey[200],
              child: Center(
                child: highlight.status == 'processing'
                    ? const CircularProgressIndicator()
                    : const Icon(Icons.movie_creation, size: 48, color: Colors.grey),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        highlight.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    _StatusChip(status: highlight.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${highlight.photoCount}장 · ${highlight.durationText}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
                if (highlight.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      highlight.errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'completed':
        color = Colors.green;
        label = '완료';
        break;
      case 'processing':
        color = Colors.orange;
        label = '생성중';
        break;
      case 'failed':
        color = Colors.red;
        label = '실패';
        break;
      default:
        color = Colors.grey;
        label = '대기';
    }
    return Chip(
      label: Text(label, style: TextStyle(color: color, fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
