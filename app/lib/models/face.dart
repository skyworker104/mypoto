class FaceCluster {
  final String id;
  final String? name;
  final int photoCount;
  final String? coverPhotoId;
  final String? coverThumbUrl;
  final String createdAt;

  FaceCluster({
    required this.id,
    this.name,
    required this.photoCount,
    this.coverPhotoId,
    this.coverThumbUrl,
    this.createdAt = '',
  });

  factory FaceCluster.fromJson(Map<String, dynamic> json) {
    return FaceCluster(
      id: json['id'],
      name: json['name'],
      photoCount: json['photo_count'] ?? 0,
      coverPhotoId: json['cover_photo_id'],
      coverThumbUrl: json['cover_thumb_url'],
      createdAt: json['created_at'] ?? '',
    );
  }
}

class AIStatus {
  final bool aiAvailable;
  final int queueSize;
  final int totalFaces;
  final int namedFaces;
  final int totalPhotoFaces;

  AIStatus({
    required this.aiAvailable,
    required this.queueSize,
    required this.totalFaces,
    required this.namedFaces,
    required this.totalPhotoFaces,
  });

  factory AIStatus.fromJson(Map<String, dynamic> json) {
    return AIStatus(
      aiAvailable: json['ai_available'] ?? false,
      queueSize: json['queue_size'] ?? 0,
      totalFaces: json['total_faces'] ?? 0,
      namedFaces: json['named_faces'] ?? 0,
      totalPhotoFaces: json['total_photo_faces'] ?? 0,
    );
  }
}
