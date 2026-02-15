import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

class SceneCategory {
  final String scene;
  final int count;

  SceneCategory({required this.scene, required this.count});

  factory SceneCategory.fromJson(Map<String, dynamic> json) {
    return SceneCategory(
      scene: json['scene'] ?? '',
      count: json['count'] ?? 0,
    );
  }

  /// Korean label mapping
  String get label {
    const labels = {
      'beach': '해변',
      'mountain': '산',
      'food': '음식',
      'building': '건물',
      'indoor': '실내',
      'outdoor': '야외',
      'nature': '자연',
      'city': '도시',
      'night': '야경',
      'portrait': '인물',
      'landscape': '풍경',
    };
    return labels[scene] ?? scene;
  }
}

final scenesProvider =
    FutureProvider<List<SceneCategory>>((ref) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get('/search/scenes');
  return (resp.data['scenes'] as List)
      .map((j) => SceneCategory.fromJson(j))
      .toList();
});
