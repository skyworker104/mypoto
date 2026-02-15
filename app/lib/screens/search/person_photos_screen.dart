import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/face_provider.dart';
import '../../widgets/photo_grid.dart';

/// Screen showing all photos of a specific person (face cluster).
class PersonPhotosScreen extends ConsumerStatefulWidget {
  final String faceId;
  final String? faceName;

  const PersonPhotosScreen({super.key, required this.faceId, this.faceName});

  @override
  ConsumerState<PersonPhotosScreen> createState() => _PersonPhotosScreenState();
}

class _PersonPhotosScreenState extends ConsumerState<PersonPhotosScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(facePhotosProvider(widget.faceId).notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(facePhotosProvider(widget.faceId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.faceName ?? '인물 사진'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: '이름 변경',
            onPressed: () => _showRenameDialog(),
          ),
        ],
      ),
      body: photosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (photos) {
          if (photos.isEmpty) {
            return const Center(child: Text('사진이 없습니다'));
          }
          return PhotoGrid(
            photos: photos,
            onPhotoTap: (photo) {
              // TODO: navigate to photo viewer
            },
            onLoadMore: () => ref
                .read(facePhotosProvider(widget.faceId).notifier)
                .loadMore(),
          );
        },
      ),
    );
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: widget.faceName ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('인물 이름 변경'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '이름을 입력하세요'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await ref
                    .read(faceListProvider.notifier)
                    .tagFace(widget.faceId, name);
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }
}
