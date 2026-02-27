import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/photo.dart';

/// Sync status for photo tiles.
enum SyncStatus { synced, pending, serverOnly, unknown }

/// Date-grouped photo grid with infinite scroll support.
/// Supports both server photos (Photo model) and local photos (AssetEntity).
class PhotoGrid extends StatefulWidget {
  final List<Photo> photos;
  final void Function(Photo photo) onPhotoTap;
  final VoidCallback onLoadMore;
  final bool isLoadingMore;
  final bool hasMore;
  final int columns;
  final Map<String, String>? httpHeaders;
  final Map<String, SyncStatus>? syncStatusMap;

  const PhotoGrid({
    super.key,
    required this.photos,
    required this.onPhotoTap,
    required this.onLoadMore,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.columns = 4,
    this.httpHeaders,
    this.syncStatusMap,
  });

  @override
  State<PhotoGrid> createState() => _PhotoGridState();
}

class _PhotoGridState extends State<PhotoGrid> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      widget.onLoadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Group photos by date.
  Map<String, List<Photo>> _groupByDate() {
    final groups = <String, List<Photo>>{};
    for (final photo in widget.photos) {
      final date = DateFormat('yyyy-MM-dd').format(photo.displayDate);
      groups.putIfAbsent(date, () => []).add(photo);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDate();
    final dates = groups.keys.toList();

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        for (final date in dates) ...[
          // Date header
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Text(
                _formatDateHeader(date),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          // Photo grid for this date
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: widget.columns,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final photo = groups[date]![index];
                  final syncStatus = widget.syncStatusMap?[photo.id];
                  return _PhotoTile(
                    photo: photo,
                    onTap: () => widget.onPhotoTap(photo),
                    httpHeaders: widget.httpHeaders,
                    syncStatus: syncStatus,
                  );
                },
                childCount: groups[date]!.length,
              ),
            ),
          ),
        ],
        // Loading indicator or end-of-list
        if (widget.isLoadingMore)
          const SliverPadding(
            padding: EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (!widget.hasMore && widget.photos.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 32, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text('모든 사진을 불러왔습니다',
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatDateHeader(String dateStr) {
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final diff = now.difference(date).inDays;

    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    if (date.year == now.year) {
      return DateFormat('M월 d일 (E)', 'ko').format(date);
    }
    return DateFormat('yyyy년 M월 d일', 'ko').format(date);
  }
}

class _PhotoTile extends StatelessWidget {
  final Photo photo;
  final VoidCallback onTap;
  final Map<String, String>? httpHeaders;
  final SyncStatus? syncStatus;

  const _PhotoTile({
    required this.photo,
    required this.onTap,
    this.httpHeaders,
    this.syncStatus,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: photo.thumbSmallUrl,
            httpHeaders: httpHeaders,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.grey[200]),
            errorWidget: (_, __, ___) =>
                const Icon(Icons.broken_image, color: Colors.grey),
          ),
          // Video indicator
          if (photo.isVideo)
            const Positioned(
              bottom: 4,
              right: 4,
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white, size: 20),
            ),
          // Favorite indicator
          if (photo.isFavorite)
            const Positioned(
              top: 4,
              right: 4,
              child: Icon(Icons.favorite, color: Colors.red, size: 16),
            ),
          // Sync status indicator
          if (syncStatus != null && syncStatus != SyncStatus.unknown)
            Positioned(
              bottom: 4,
              left: 4,
              child: _buildSyncIcon(syncStatus!),
            ),
        ],
      ),
    );
  }

  Widget _buildSyncIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return const Icon(Icons.cloud_done, size: 14, color: Colors.white70);
      case SyncStatus.pending:
        return const Icon(Icons.cloud_upload, size: 14, color: Colors.orangeAccent);
      case SyncStatus.serverOnly:
        return const Icon(Icons.cloud, size: 14, color: Colors.lightBlue);
      case SyncStatus.unknown:
        return const SizedBox.shrink();
    }
  }
}

/// Local photo grid for offline mode (displays AssetEntity thumbnails).
class LocalPhotoGrid extends StatefulWidget {
  final List<AssetEntity> photos;
  final void Function(AssetEntity asset)? onPhotoTap;
  final VoidCallback onLoadMore;
  final bool isLoadingMore;
  final bool hasMore;
  final int columns;
  final bool Function(String assetId)? isAssetSynced;

  const LocalPhotoGrid({
    super.key,
    required this.photos,
    this.onPhotoTap,
    required this.onLoadMore,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.columns = 4,
    this.isAssetSynced,
  });

  @override
  State<LocalPhotoGrid> createState() => _LocalPhotoGridState();
}

class _LocalPhotoGridState extends State<LocalPhotoGrid> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      widget.onLoadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Group photos by date.
  Map<String, List<AssetEntity>> _groupByDate() {
    final groups = <String, List<AssetEntity>>{};
    for (final asset in widget.photos) {
      final date = DateFormat('yyyy-MM-dd')
          .format(asset.createDateTime);
      groups.putIfAbsent(date, () => []).add(asset);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDate();
    final dates = groups.keys.toList();

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        for (final date in dates) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Text(
                _formatDateHeader(date),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: widget.columns,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final asset = groups[date]![index];
                  final synced = widget.isAssetSynced?.call(asset.id) ?? false;
                  return _LocalPhotoTile(
                    asset: asset,
                    onTap: widget.onPhotoTap != null
                        ? () => widget.onPhotoTap!(asset)
                        : null,
                    isSynced: synced,
                  );
                },
                childCount: groups[date]!.length,
              ),
            ),
          ),
        ],
        if (widget.isLoadingMore)
          const SliverPadding(
            padding: EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (!widget.hasMore && widget.photos.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 32, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text('모든 사진을 불러왔습니다',
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatDateHeader(String dateStr) {
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final diff = now.difference(date).inDays;

    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    if (date.year == now.year) {
      return DateFormat('M월 d일 (E)', 'ko').format(date);
    }
    return DateFormat('yyyy년 M월 d일', 'ko').format(date);
  }
}

class _LocalPhotoTile extends StatelessWidget {
  final AssetEntity asset;
  final VoidCallback? onTap;
  final bool isSynced;

  const _LocalPhotoTile({
    required this.asset,
    this.onTap,
    this.isSynced = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(
              const ThumbnailSize(200, 200),
              quality: 80,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                );
              }
              return Container(color: Colors.grey[200]);
            },
          ),
          // Video indicator
          if (asset.type == AssetType.video)
            const Positioned(
              bottom: 4,
              right: 4,
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white, size: 20),
            ),
          // Sync status indicator
          Positioned(
            bottom: 4,
            left: 4,
            child: Icon(
              isSynced ? Icons.cloud_done : Icons.cloud_upload,
              size: 14,
              color: isSynced ? Colors.white70 : Colors.orangeAccent,
            ),
          ),
        ],
      ),
    );
  }
}
