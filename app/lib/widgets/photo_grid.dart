import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/photo.dart';
import 'justified_layout.dart';

/// Sync status for photo tiles.
enum SyncStatus { synced, pending, serverOnly, unknown }

// ---------------------------------------------------------------------------
// PhotoGrid — server photos with justified layout
// ---------------------------------------------------------------------------

/// Date-grouped photo grid with Google Photos-style justified layout.
class PhotoGrid extends StatefulWidget {
  final List<Photo> photos;
  final void Function(Photo photo) onPhotoTap;
  final VoidCallback onLoadMore;
  final bool isLoadingMore;
  final bool hasMore;
  final Map<String, String>? httpHeaders;
  final Map<String, SyncStatus>? syncStatusMap;

  const PhotoGrid({
    super.key,
    required this.photos,
    required this.onPhotoTap,
    required this.onLoadMore,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.httpHeaders,
    this.syncStatusMap,
  });

  @override
  State<PhotoGrid> createState() => _PhotoGridState();
}

class _PhotoGridState extends State<PhotoGrid> {
  final _scrollController = ScrollController();
  double? _lastWidth;
  int? _lastPhotoCount;
  Map<String, List<JustifiedRow<Photo>>>? _cachedLayout;

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

  @override
  void didUpdateWidget(covariant PhotoGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photos.length != widget.photos.length) {
      _cachedLayout = null;
    }
  }

  Map<String, List<Photo>> _groupByDate() {
    final groups = <String, List<Photo>>{};
    for (final photo in widget.photos) {
      final date = DateFormat('yyyy-MM-dd').format(photo.displayDate);
      groups.putIfAbsent(date, () => []).add(photo);
    }
    return groups;
  }

  Map<String, List<JustifiedRow<Photo>>> _computeLayout(
      Map<String, List<Photo>> groups, double containerWidth) {
    final targetHeight = getTargetRowHeight(containerWidth);
    final result = <String, List<JustifiedRow<Photo>>>{};

    for (final entry in groups.entries) {
      final items = entry.value.map((photo) {
        final w = photo.width ?? 4;
        final h = photo.height ?? 3;
        final aspect = (w > 0 && h > 0) ? w / h : 4.0 / 3.0;
        return JustifiedItem(data: photo, aspect: aspect);
      }).toList();

      result[entry.key] = computeJustifiedLayout(
        items: items,
        containerWidth: containerWidth,
        targetRowHeight: targetHeight,
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDate();
    final dates = groups.keys.toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth - 4; // 2px padding each side

        if (_lastWidth != containerWidth ||
            _lastPhotoCount != widget.photos.length ||
            _cachedLayout == null) {
          _lastWidth = containerWidth;
          _lastPhotoCount = widget.photos.length;
          _cachedLayout = _computeLayout(groups, containerWidth);
        }

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
              // Justified rows
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final row = _cachedLayout![date]![index];
                      return _buildJustifiedRow(row);
                    },
                    childCount: _cachedLayout![date]?.length ?? 0,
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
      },
    );
  }

  Widget _buildJustifiedRow(JustifiedRow<Photo> row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          for (var i = 0; i < row.items.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            if (i == row.items.length - 1)
              // Last item: Expanded to absorb sub-pixel rounding
              Expanded(
                child: SizedBox(
                  height: row.height.floorToDouble(),
                  child: _PhotoTile(
                    photo: row.items[i].data,
                    onTap: () => widget.onPhotoTap(row.items[i].data),
                    httpHeaders: widget.httpHeaders,
                    syncStatus:
                        widget.syncStatusMap?[row.items[i].data.id],
                  ),
                ),
              )
            else
              SizedBox(
                width: (row.items[i].aspect * row.height).floorToDouble(),
                height: row.height.floorToDouble(),
                child: _PhotoTile(
                  photo: row.items[i].data,
                  onTap: () => widget.onPhotoTap(row.items[i].data),
                  httpHeaders: widget.httpHeaders,
                  syncStatus:
                      widget.syncStatusMap?[row.items[i].data.id],
                ),
              ),
          ],
        ],
      ),
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
        return const Icon(Icons.cloud_upload,
            size: 14, color: Colors.orangeAccent);
      case SyncStatus.serverOnly:
        return const Icon(Icons.cloud, size: 14, color: Colors.lightBlue);
      case SyncStatus.unknown:
        return const SizedBox.shrink();
    }
  }
}

// ---------------------------------------------------------------------------
// LocalPhotoGrid — device photos with justified layout
// ---------------------------------------------------------------------------

/// Local photo grid for offline mode with Google Photos-style justified layout.
class LocalPhotoGrid extends StatefulWidget {
  final List<AssetEntity> photos;
  final void Function(AssetEntity asset)? onPhotoTap;
  final VoidCallback onLoadMore;
  final bool isLoadingMore;
  final bool hasMore;
  final bool Function(String assetId)? isAssetSynced;

  const LocalPhotoGrid({
    super.key,
    required this.photos,
    this.onPhotoTap,
    required this.onLoadMore,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.isAssetSynced,
  });

  @override
  State<LocalPhotoGrid> createState() => _LocalPhotoGridState();
}

class _LocalPhotoGridState extends State<LocalPhotoGrid> {
  final _scrollController = ScrollController();
  double? _lastWidth;
  int? _lastPhotoCount;
  Map<String, List<JustifiedRow<AssetEntity>>>? _cachedLayout;

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

  @override
  void didUpdateWidget(covariant LocalPhotoGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photos.length != widget.photos.length) {
      _cachedLayout = null;
    }
  }

  Map<String, List<AssetEntity>> _groupByDate() {
    final groups = <String, List<AssetEntity>>{};
    for (final asset in widget.photos) {
      final date = DateFormat('yyyy-MM-dd').format(asset.createDateTime);
      groups.putIfAbsent(date, () => []).add(asset);
    }
    return groups;
  }

  Map<String, List<JustifiedRow<AssetEntity>>> _computeLayout(
      Map<String, List<AssetEntity>> groups, double containerWidth) {
    final targetHeight = getTargetRowHeight(containerWidth);
    final result = <String, List<JustifiedRow<AssetEntity>>>{};

    for (final entry in groups.entries) {
      final items = entry.value.map((asset) {
        final w = asset.width;
        final h = asset.height;
        final aspect = (w > 0 && h > 0) ? w / h : 4.0 / 3.0;
        return JustifiedItem(data: asset, aspect: aspect);
      }).toList();

      result[entry.key] = computeJustifiedLayout(
        items: items,
        containerWidth: containerWidth,
        targetRowHeight: targetHeight,
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDate();
    final dates = groups.keys.toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth - 4;

        if (_lastWidth != containerWidth ||
            _lastPhotoCount != widget.photos.length ||
            _cachedLayout == null) {
          _lastWidth = containerWidth;
          _lastPhotoCount = widget.photos.length;
          _cachedLayout = _computeLayout(groups, containerWidth);
        }

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
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final row = _cachedLayout![date]![index];
                      return _buildJustifiedRow(row);
                    },
                    childCount: _cachedLayout![date]?.length ?? 0,
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
      },
    );
  }

  Widget _buildJustifiedRow(JustifiedRow<AssetEntity> row) {
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          for (var i = 0; i < row.items.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            if (i == row.items.length - 1)
              Expanded(
                child: SizedBox(
                  height: row.height.floorToDouble(),
                  child: _LocalPhotoTile(
                    asset: row.items[i].data,
                    onTap: widget.onPhotoTap != null
                        ? () => widget.onPhotoTap!(row.items[i].data)
                        : null,
                    isSynced:
                        widget.isAssetSynced?.call(row.items[i].data.id) ??
                            false,
                    thumbWidth:
                        (row.items[i].aspect * row.height * dpr).toInt().clamp(100, 600),
                    thumbHeight:
                        (row.height * dpr).toInt().clamp(100, 600),
                  ),
                ),
              )
            else
              SizedBox(
                width:
                    (row.items[i].aspect * row.height).floorToDouble(),
                height: row.height.floorToDouble(),
                child: _LocalPhotoTile(
                  asset: row.items[i].data,
                  onTap: widget.onPhotoTap != null
                      ? () => widget.onPhotoTap!(row.items[i].data)
                      : null,
                  isSynced:
                      widget.isAssetSynced?.call(row.items[i].data.id) ??
                          false,
                  thumbWidth:
                      (row.items[i].aspect * row.height * dpr).toInt().clamp(100, 600),
                  thumbHeight:
                      (row.height * dpr).toInt().clamp(100, 600),
                ),
              ),
          ],
        ],
      ),
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
  final int thumbWidth;
  final int thumbHeight;

  const _LocalPhotoTile({
    required this.asset,
    this.onTap,
    this.isSynced = false,
    this.thumbWidth = 200,
    this.thumbHeight = 200,
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
              ThumbnailSize(thumbWidth, thumbHeight),
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
