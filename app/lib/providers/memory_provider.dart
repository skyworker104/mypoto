import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

class MemoryGroup {
  final String type;
  final int year;
  final int yearsAgo;
  final String date;
  final int photoCount;
  final List<MemoryPhoto> photos;

  MemoryGroup({
    required this.type,
    required this.year,
    required this.yearsAgo,
    required this.date,
    required this.photoCount,
    required this.photos,
  });

  factory MemoryGroup.fromJson(Map<String, dynamic> json) {
    return MemoryGroup(
      type: json['type'] ?? '',
      year: json['year'] ?? 0,
      yearsAgo: json['years_ago'] ?? 0,
      date: json['date'] ?? '',
      photoCount: json['photo_count'] ?? 0,
      photos: (json['photos'] as List? ?? [])
          .map((p) => MemoryPhoto.fromJson(p))
          .toList(),
    );
  }
}

class MemoryPhoto {
  final String id;
  final String? thumbUrl;
  final String? takenAt;
  final String? location;

  MemoryPhoto({
    required this.id,
    this.thumbUrl,
    this.takenAt,
    this.location,
  });

  factory MemoryPhoto.fromJson(Map<String, dynamic> json) {
    return MemoryPhoto(
      id: json['id'],
      thumbUrl: json['thumb_url'],
      takenAt: json['taken_at'],
      location: json['location'],
    );
  }
}

final memoriesProvider =
    FutureProvider<List<MemoryGroup>>((ref) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get('/memories');
  return (resp.data['memories'] as List)
      .map((j) => MemoryGroup.fromJson(j))
      .toList();
});
