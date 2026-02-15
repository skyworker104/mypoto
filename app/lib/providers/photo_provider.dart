import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../models/photo.dart';
import '../services/api_client.dart';
import 'auth_provider.dart';

/// Photo timeline state.
class PhotoTimelineState {
  final List<Photo> photos;
  final String? nextCursor;
  final int totalCount;
  final bool isLoading;

  const PhotoTimelineState({
    this.photos = const [],
    this.nextCursor,
    this.totalCount = 0,
    this.isLoading = false,
  });

  PhotoTimelineState copyWith({
    List<Photo>? photos,
    String? nextCursor,
    int? totalCount,
    bool? isLoading,
  }) {
    return PhotoTimelineState(
      photos: photos ?? this.photos,
      nextCursor: nextCursor ?? this.nextCursor,
      totalCount: totalCount ?? this.totalCount,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class PhotoTimelineNotifier extends StateNotifier<PhotoTimelineState> {
  final ApiClient _api;

  PhotoTimelineNotifier(this._api) : super(const PhotoTimelineState());

  /// Server base URL without API prefix (e.g. http://host:port).
  String get _serverUrl =>
      (_api.baseUrl ?? '').replaceAll(AppConfig.apiPrefix, '');

  /// Load first page.
  Future<void> loadInitial({int limit = 50}) async {
    state = state.copyWith(isLoading: true);
    try {
      final resp = await _api.get('/photos', queryParams: {'limit': limit});
      final data = PhotoList.fromJson(resp.data, serverUrl: _serverUrl);
      state = PhotoTimelineState(
        photos: data.photos,
        nextCursor: data.nextCursor,
        totalCount: data.totalCount,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Load next page (infinite scroll).
  Future<void> loadMore({int limit = 50}) async {
    if (state.isLoading || state.nextCursor == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final resp = await _api.get('/photos', queryParams: {
        'cursor': state.nextCursor,
        'limit': limit,
      });
      final data = PhotoList.fromJson(resp.data, serverUrl: _serverUrl);
      state = PhotoTimelineState(
        photos: [...state.photos, ...data.photos],
        nextCursor: data.nextCursor,
        totalCount: data.totalCount,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Toggle favorite.
  Future<void> toggleFavorite(String photoId) async {
    final idx = state.photos.indexWhere((p) => p.id == photoId);
    if (idx < 0) return;
    final current = state.photos[idx].isFavorite;
    try {
      await _api.patch('/photos/$photoId', data: {'is_favorite': !current});
      // Reload to get updated data
      await loadInitial();
    } catch (_) {}
  }

  /// Delete photo.
  Future<void> deletePhoto(String photoId) async {
    try {
      await _api.delete('/photos/$photoId');
      state = state.copyWith(
        photos: state.photos.where((p) => p.id != photoId).toList(),
        totalCount: state.totalCount - 1,
      );
    } catch (_) {}
  }
}

final photoTimelineProvider =
    StateNotifierProvider<PhotoTimelineNotifier, PhotoTimelineState>((ref) {
  return PhotoTimelineNotifier(ref.read(apiClientProvider));
});
