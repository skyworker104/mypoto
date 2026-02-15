import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

/// State for local device photos.
class LocalPhotoState {
  final List<AssetEntity> photos;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;

  const LocalPhotoState({
    this.photos = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 0,
  });

  LocalPhotoState copyWith({
    List<AssetEntity>? photos,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
  }) {
    return LocalPhotoState(
      photos: photos ?? this.photos,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
    );
  }
}

class LocalPhotoNotifier extends StateNotifier<LocalPhotoState> {
  static const _pageSize = 200;

  LocalPhotoNotifier() : super(const LocalPhotoState());

  /// Load first page of local photos.
  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);

    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
      );
      if (albums.isEmpty) {
        state = state.copyWith(isLoading: false, hasMore: false);
        return;
      }

      // Use the "All" album
      final allAlbum = albums.firstWhere(
        (a) => a.isAll,
        orElse: () => albums.first,
      );

      final assets = await allAlbum.getAssetListPaged(
        page: 0,
        size: _pageSize,
      );

      state = LocalPhotoState(
        photos: assets,
        isLoading: false,
        hasMore: assets.length >= _pageSize,
        currentPage: 0,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Load more local photos.
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);

    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
      );
      if (albums.isEmpty) {
        state = state.copyWith(isLoading: false, hasMore: false);
        return;
      }

      final allAlbum = albums.firstWhere(
        (a) => a.isAll,
        orElse: () => albums.first,
      );

      final nextPage = state.currentPage + 1;
      final assets = await allAlbum.getAssetListPaged(
        page: nextPage,
        size: _pageSize,
      );

      state = state.copyWith(
        photos: [...state.photos, ...assets],
        isLoading: false,
        hasMore: assets.length >= _pageSize,
        currentPage: nextPage,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }
}

final localPhotoProvider =
    StateNotifierProvider<LocalPhotoNotifier, LocalPhotoState>((ref) {
  return LocalPhotoNotifier();
});
