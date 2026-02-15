import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

class PhotoLocation {
  final String id;
  final double lat;
  final double lon;
  final String? locationName;
  final String? thumbUrl;
  final String? takenAt;

  PhotoLocation({
    required this.id,
    required this.lat,
    required this.lon,
    this.locationName,
    this.thumbUrl,
    this.takenAt,
  });

  factory PhotoLocation.fromJson(Map<String, dynamic> json) {
    return PhotoLocation(
      id: json['id'],
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      locationName: json['location_name'],
      thumbUrl: json['thumb_url'],
      takenAt: json['taken_at'],
    );
  }
}

class LocationCluster {
  final double lat;
  final double lon;
  final int count;
  final String? locationName;
  final String? coverThumbUrl;
  final List<String> photoIds;

  LocationCluster({
    required this.lat,
    required this.lon,
    required this.count,
    this.locationName,
    this.coverThumbUrl,
    this.photoIds = const [],
  });

  factory LocationCluster.fromJson(Map<String, dynamic> json) {
    return LocationCluster(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      count: json['count'] ?? 0,
      locationName: json['location_name'],
      coverThumbUrl: json['cover_thumb_url'],
      photoIds: (json['photo_ids'] as List?)?.cast<String>() ?? [],
    );
  }
}

final mapClustersProvider =
    FutureProvider<List<LocationCluster>>((ref) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get('/map/clusters', queryParams: {'precision': 2});
  return (resp.data['clusters'] as List)
      .map((j) => LocationCluster.fromJson(j))
      .toList();
});

final mapPhotosProvider =
    FutureProvider<List<PhotoLocation>>((ref) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get('/map/photos');
  return (resp.data['photos'] as List)
      .map((j) => PhotoLocation.fromJson(j))
      .toList();
});
