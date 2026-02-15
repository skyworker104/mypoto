import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../models/face.dart';
import '../models/photo.dart';
import '../services/api_client.dart';
import 'auth_provider.dart';

// Face list provider
final faceListProvider =
    StateNotifierProvider<FaceListNotifier, AsyncValue<List<FaceCluster>>>(
        (ref) {
  return FaceListNotifier(ref.read(apiClientProvider));
});

class FaceListNotifier extends StateNotifier<AsyncValue<List<FaceCluster>>> {
  final ApiClient _api;
  FaceListNotifier(this._api) : super(const AsyncValue.loading());

  Future<void> load({int minPhotos = 2}) async {
    state = const AsyncValue.loading();
    try {
      final resp =
          await _api.get('/faces', queryParams: {'min_photos': minPhotos});
      final faces = (resp.data['faces'] as List)
          .map((j) => FaceCluster.fromJson(j))
          .toList();
      state = AsyncValue.data(faces);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> tagFace(String faceId, String name) async {
    await _api.patch('/faces/$faceId', data: {'name': name});
    // Reload list
    await load();
  }
}

// Face photos provider (per face ID)
final facePhotosProvider = StateNotifierProvider.family<FacePhotosNotifier,
    AsyncValue<List<Photo>>, String>((ref, faceId) {
  return FacePhotosNotifier(ref.read(apiClientProvider), faceId);
});

class FacePhotosNotifier extends StateNotifier<AsyncValue<List<Photo>>> {
  final ApiClient _api;
  final String faceId;
  String? _nextCursor;

  FacePhotosNotifier(this._api, this.faceId)
      : super(const AsyncValue.loading());

  String get _serverUrl =>
      (_api.baseUrl ?? '').replaceAll(AppConfig.apiPrefix, '');

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final resp = await _api.get('/faces/$faceId/photos');
      final photos = (resp.data['photos'] as List)
          .map((j) => Photo.fromJson(j, serverUrl: _serverUrl))
          .toList();
      _nextCursor = resp.data['next_cursor'];
      state = AsyncValue.data(photos);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    if (_nextCursor == null) return;
    final current = state.valueOrNull ?? [];
    try {
      final resp = await _api
          .get('/faces/$faceId/photos', queryParams: {'cursor': _nextCursor});
      final photos = (resp.data['photos'] as List)
          .map((j) => Photo.fromJson(j, serverUrl: _serverUrl))
          .toList();
      _nextCursor = resp.data['next_cursor'];
      state = AsyncValue.data([...current, ...photos]);
    } catch (_) {}
  }
}

// AI status provider
final aiStatusProvider = FutureProvider<AIStatus>((ref) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get('/faces/status');
  return AIStatus.fromJson(resp.data);
});
