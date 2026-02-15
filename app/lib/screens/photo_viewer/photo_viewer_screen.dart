import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/photo_provider.dart';


/// Full-screen photo viewer with swipe navigation and actions.
class PhotoViewerScreen extends ConsumerStatefulWidget {
  final String photoId;

  const PhotoViewerScreen({super.key, required this.photoId});

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  late PageController _pageController;
  bool _showOverlay = true;
  bool _editingDesc = false;
  final _descController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final photos = ref.read(photoTimelineProvider).photos;
    final idx = photos.indexWhere((p) => p.id == widget.photoId);
    _pageController = PageController(initialPage: idx >= 0 ? idx : 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoTimelineProvider);
    final api = ref.read(apiClientProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showOverlay = !_showOverlay),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: state.photos.length,
              onPageChanged: (_) => setState(() => _editingDesc = false),
              itemBuilder: (_, index) {
                final photo = state.photos[index];
                return InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: photo.thumbMediumUrl,
                      fit: BoxFit.contain,
                      httpHeaders: {
                        if (api.accessToken != null)
                          'Authorization': 'Bearer ${api.accessToken}',
                      },
                      placeholder: (_, __) =>
                          const CircularProgressIndicator(color: Colors.white),
                      errorWidget: (_, __, ___) =>
                          const Icon(Icons.error, color: Colors.white),
                    ),
                  ),
                );
              },
            ),
            // Top overlay
            if (_showOverlay)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.share, color: Colors.white),
                          onPressed: () {},
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert,
                              color: Colors.white),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Bottom overlay with info and actions
            if (_showOverlay && state.photos.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomBar(context, state),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, PhotoTimelineState state) {
    final page = _pageController.hasClients
        ? (_pageController.page?.round() ?? 0)
        : 0;
    if (page >= state.photos.length) return const SizedBox.shrink();

    final photo = state.photos[page];
    final profile = ref.read(authProvider.notifier).profile;
    final isOwner = profile != null && photo.userId == profile.id;
    final dateStr = photo.takenAt ?? photo.createdAt;
    final date = DateTime.tryParse(dateStr) ?? DateTime.now();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat('yyyy년 M월 d일 (E) HH:mm', 'ko').format(date),
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          if (photo.locationName != null)
            Text(photo.locationName!,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          if (photo.uploadedBy != null)
            Text('${photo.uploadedBy} 님이 업로드',
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
          // Description display/edit
          if (!_editingDesc) ...[
            GestureDetector(
              onTap: () {
                _descController.text = photo.description ?? '';
                setState(() => _editingDesc = true);
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        photo.description ?? '설명 추가...',
                        style: TextStyle(
                          color: photo.description != null
                              ? Colors.white70
                              : Colors.white38,
                          fontSize: 12,
                          fontStyle: photo.description != null
                              ? FontStyle.normal
                              : FontStyle.italic,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.edit, color: Colors.white38, size: 14),
                  ],
                ),
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _descController,
                      autofocus: true,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: '설명을 입력하세요',
                        hintStyle: TextStyle(color: Colors.white38),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white38),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    iconSize: 20,
                    onPressed: () => _saveDescription(photo.id),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    iconSize: 20,
                    onPressed: () => setState(() => _editingDesc = false),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ActionButton(
                icon: photo.isFavorite
                    ? Icons.favorite
                    : Icons.favorite_border,
                label: '좋아요',
                color: photo.isFavorite ? Colors.red : Colors.white,
                onTap: () {
                  ref
                      .read(photoTimelineProvider.notifier)
                      .toggleFavorite(photo.id);
                },
              ),
              _ActionButton(
                icon: Icons.comment_outlined,
                label: '댓글',
                onTap: () {},
              ),
              _ActionButton(
                icon: Icons.photo_album_outlined,
                label: '앨범',
                onTap: () {},
              ),
              if (isOwner)
                _ActionButton(
                  icon: Icons.delete_outline,
                  label: '삭제',
                  onTap: () {
                    ref
                        .read(photoTimelineProvider.notifier)
                        .deletePhoto(photo.id);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveDescription(String photoId) async {
    final desc = _descController.text.trim();
    try {
      final api = ref.read(apiClientProvider);
      await api.patch('/photos/$photoId',
          data: {'description': desc.isEmpty ? null : desc});
      // Reload to reflect changes
      ref.read(photoTimelineProvider.notifier).loadInitial();
      setState(() => _editingDesc = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장 실패')),
        );
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}
