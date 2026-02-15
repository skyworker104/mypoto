import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/face_provider.dart';
import '../../providers/scene_provider.dart';
import 'person_photos_screen.dart';

/// Search tab with person (face) browsing and text search.
class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(faceListProvider.notifier).load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final facesAsync = ref.watch(faceListProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: '사진 검색...',
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search),
          ),
          onSubmitted: (query) {
            // TODO: implement text search in Sprint 11
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Person section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('인물',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () =>
                      ref.read(faceListProvider.notifier).load(minPhotos: 1),
                  child: const Text('모두 보기'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            facesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('인물 로딩 실패: $e')),
              data: (faces) {
                if (faces.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.face, size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('감지된 인물이 없습니다',
                              style: TextStyle(color: Colors.grey)),
                          Text('사진을 업로드하면 AI가 자동으로 인물을 감지합니다',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                  );
                }
                return SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: faces.length,
                    itemBuilder: (context, index) {
                      final face = faces[index];
                      return _PersonCircle(
                        face: face,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PersonPhotosScreen(faceId: face.id, faceName: face.name),
                          ),
                        ),
                        onLongPress: () => _showTagDialog(face.id, face.name),
                      );
                    },
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Scene categories section
            Text('장면 카테고리',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ref.watch(scenesProvider).when(
              loading: () => const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CategoryChip(icon: Icons.favorite, label: '즐겨찾기'),
                  _CategoryChip(icon: Icons.videocam, label: '동영상'),
                  _CategoryChip(icon: Icons.location_on, label: '장소별'),
                  _CategoryChip(icon: Icons.calendar_today, label: '날짜별'),
                ],
              ),
              error: (_, __) => const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CategoryChip(icon: Icons.favorite, label: '즐겨찾기'),
                  _CategoryChip(icon: Icons.videocam, label: '동영상'),
                ],
              ),
              data: (scenes) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const _CategoryChip(icon: Icons.favorite, label: '즐겨찾기'),
                  const _CategoryChip(icon: Icons.videocam, label: '동영상'),
                  const _CategoryChip(icon: Icons.location_on, label: '장소별'),
                  const _CategoryChip(icon: Icons.map, label: '지도'),
                  ...scenes.map((s) => _CategoryChip(
                    icon: _sceneIcon(s.scene),
                    label: '${s.label} (${s.count})',
                  )),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // AI status
            ref.watch(aiStatusProvider).when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (status) => Card(
                child: ListTile(
                  leading: Icon(
                    status.aiAvailable ? Icons.smart_toy : Icons.smart_toy_outlined,
                    color: status.aiAvailable ? Colors.green : Colors.grey,
                  ),
                  title: Text(status.aiAvailable ? 'AI 활성' : 'AI 비활성'),
                  subtitle: Text(
                    '인물 ${status.totalFaces}명 감지 · '
                    '${status.namedFaces}명 태그됨 · '
                    '${status.totalPhotoFaces}개 얼굴',
                  ),
                  trailing: status.queueSize > 0
                      ? Chip(label: Text('처리중 ${status.queueSize}'))
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTagDialog(String faceId, String? currentName) {
    final controller = TextEditingController(text: currentName ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('인물 이름 태그'),
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
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(faceListProvider.notifier).tagFace(faceId, name);
              }
              Navigator.pop(ctx);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }
}

class _PersonCircle extends StatelessWidget {
  final dynamic face;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PersonCircle({
    required this.face,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: Colors.grey[300],
              backgroundImage: face.coverThumbUrl != null
                  ? CachedNetworkImageProvider(face.coverThumbUrl!)
                  : null,
              child: face.coverThumbUrl == null
                  ? const Icon(Icons.person, size: 36, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 72,
              child: Text(
                face.name ?? '이름 없음',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: face.name != null ? null : Colors.grey,
                ),
              ),
            ),
            Text(
              '${face.photoCount}장',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _sceneIcon(String scene) {
  const icons = {
    'beach': Icons.beach_access,
    'mountain': Icons.terrain,
    'food': Icons.restaurant,
    'building': Icons.apartment,
    'indoor': Icons.home,
    'outdoor': Icons.park,
    'nature': Icons.forest,
    'city': Icons.location_city,
    'night': Icons.nightlight,
    'portrait': Icons.portrait,
    'landscape': Icons.landscape,
  };
  return icons[scene] ?? Icons.photo;
}

class _CategoryChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CategoryChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: () {
        // TODO: implement category search
      },
    );
  }
}
