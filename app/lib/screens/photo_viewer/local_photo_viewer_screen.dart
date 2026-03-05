import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

/// Full-screen viewer for local device photos with swipe navigation.
class LocalPhotoViewerScreen extends StatefulWidget {
  final List<AssetEntity> photos;
  final int initialIndex;

  const LocalPhotoViewerScreen({
    super.key,
    required this.photos,
    this.initialIndex = 0,
  });

  @override
  State<LocalPhotoViewerScreen> createState() => _LocalPhotoViewerScreenState();
}

class _LocalPhotoViewerScreenState extends State<LocalPhotoViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showOverlay = true;

  // Video player
  VideoPlayerController? _videoController;
  int _currentVideoIndex = -1;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.photos.length - 1);
    _pageController = PageController(initialPage: _currentIndex);

    final asset = widget.photos[_currentIndex];
    if (asset.type == AssetType.video) {
      _initVideoPlayer(_currentIndex, asset);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initVideoPlayer(int index, AssetEntity asset) async {
    _videoController?.dispose();
    _videoController = null;
    _currentVideoIndex = index;

    final file = await asset.file;
    if (file == null || !mounted) return;

    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    if (!mounted) {
      controller.dispose();
      return;
    }

    setState(() {
      _videoController = controller;
    });
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });

    final asset = widget.photos[index];
    if (asset.type == AssetType.video) {
      _initVideoPlayer(index, asset);
    } else {
      _videoController?.pause();
      _currentVideoIndex = -1;
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showOverlay = !_showOverlay),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (_, index) {
                final asset = widget.photos[index];
                if (asset.type == AssetType.video) {
                  return _buildVideoView(index);
                }
                return _buildPhotoView(asset);
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
                        Text(
                          '${_currentIndex + 1} / ${widget.photos.length}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(width: 16),
                      ],
                    ),
                  ),
                ),
              ),
            // Bottom overlay
            if (_showOverlay)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomInfo(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoView(AssetEntity asset) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(
        ThumbnailSize(
          (MediaQuery.sizeOf(context).width *
                  MediaQuery.devicePixelRatioOf(context))
              .toInt(),
          (MediaQuery.sizeOf(context).height *
                  MediaQuery.devicePixelRatioOf(context))
              .toInt(),
        ),
        quality: 95,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: Center(
              child: Image.memory(
                snapshot.data!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          );
        }
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      },
    );
  }

  Widget _buildVideoView(int index) {
    final ctl = (index == _currentVideoIndex) ? _videoController : null;
    final ready = ctl != null && ctl.value.isInitialized;

    return Center(
      child: ready
          ? Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: ctl.value.aspectRatio,
                  child: VideoPlayer(ctl),
                ),
                if (!ctl.value.isPlaying)
                  GestureDetector(
                    onTap: () {
                      ctl.play();
                      setState(() {});
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(40),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: const Icon(Icons.play_arrow,
                          color: Colors.white, size: 48),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () {
                      ctl.pause();
                      setState(() {});
                    },
                    child: const SizedBox.expand(),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: VideoProgressIndicator(
                    ctl,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Colors.white,
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ValueListenableBuilder(
                      valueListenable: ctl,
                      builder: (_, value, __) => Text(
                        '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : const CircularProgressIndicator(color: Colors.white),
    );
  }

  Widget _buildBottomInfo() {
    if (_currentIndex >= widget.photos.length) {
      return const SizedBox.shrink();
    }

    final asset = widget.photos[_currentIndex];
    final date = asset.createDateTime;
    final isVideo = asset.type == AssetType.video;

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
          Row(
            children: [
              if (isVideo) ...[
                const Icon(Icons.videocam, color: Colors.white70, size: 16),
                const SizedBox(width: 4),
              ],
              Text(
                DateFormat('yyyy년 M월 d일 (E) HH:mm', 'ko').format(date),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
          if (asset.title != null && asset.title!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                asset.title!,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${asset.width} × ${asset.height}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
