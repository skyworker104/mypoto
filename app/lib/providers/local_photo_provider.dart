import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

/// State for local device photos.
class LocalPhotoState {
  final List<AssetEntity> photos;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final List<AssetEntity> _allAssets;

  const LocalPhotoState({
    this.photos = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 0,
    List<AssetEntity> allAssets = const [],
  }) : _allAssets = allAssets;

  LocalPhotoState copyWith({
    List<AssetEntity>? photos,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    List<AssetEntity>? allAssets,
  }) {
    return LocalPhotoState(
      photos: photos ?? this.photos,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      allAssets: allAssets ?? _allAssets,
    );
  }
}

class LocalPhotoNotifier extends StateNotifier<LocalPhotoState> {
  static const _pageSize = 200;

  LocalPhotoNotifier() : super(const LocalPhotoState());

  /// Load first page of local photos, optionally filtered by album IDs.
  Future<void> load({List<String>? albumFilter}) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);

    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
      );
      if (albums.isEmpty) {
        state = const LocalPhotoState(isLoading: false, hasMore: false);
        return;
      }

      // Determine target albums
      List<AssetPathEntity> targetAlbums;
      if (albumFilter != null && albumFilter.isNotEmpty) {
        targetAlbums =
            albums.where((a) => albumFilter.contains(a.id)).toList();
        if (targetAlbums.isEmpty) {
          state = const LocalPhotoState(isLoading: false, hasMore: false);
          return;
        }
      } else {
        // No filter: use "All" album (original behavior)
        final allAlbum = albums.firstWhere(
          (a) => a.isAll,
          orElse: () => albums.first,
        );
        targetAlbums = [allAlbum];
      }

      // Collect all assets from target albums
      List<AssetEntity> allAssets = [];
      for (final album in targetAlbums) {
        final count = await album.assetCountAsync;
        final assets = await album.getAssetListRange(start: 0, end: count);
        allAssets.addAll(assets);
      }

      // Deduplicate by ID
      final seen = <String>{};
      allAssets = allAssets.where((a) => seen.add(a.id)).toList();

      // Sort by creation date descending (newest first)
      allAssets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

      // Expose first page
      final pageEnd = _pageSize.clamp(0, allAssets.length);
      final firstPage = allAssets.sublist(0, pageEnd);

      state = LocalPhotoState(
        photos: firstPage,
        isLoading: false,
        hasMore: pageEnd < allAssets.length,
        currentPage: 0,
        allAssets: allAssets,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Load more local photos from cached asset list.
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);

    final start = (state.currentPage + 1) * _pageSize;
    if (start >= state._allAssets.length) {
      state = state.copyWith(isLoading: false, hasMore: false);
      return;
    }

    final end = (start + _pageSize).clamp(0, state._allAssets.length);
    final nextAssets = state._allAssets.sublist(start, end);

    state = state.copyWith(
      photos: [...state.photos, ...nextAssets],
      isLoading: false,
      hasMore: end < state._allAssets.length,
      currentPage: state.currentPage + 1,
    );
  }
}

final localPhotoProvider =
    StateNotifierProvider<LocalPhotoNotifier, LocalPhotoState>((ref) {
  return LocalPhotoNotifier();
});
