/// Photo data models.
class Photo {
  final String id;
  final String userId;
  final String? uploadedBy;
  final String fileHash;
  final int fileSize;
  final String mimeType;
  final int? width;
  final int? height;
  final String? takenAt;
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final String? cameraMake;
  final String? cameraModel;
  final String? description;
  final bool isFavorite;
  final bool isVideo;
  final double? duration;
  final String createdAt;
  final String thumbSmallUrl;
  final String thumbMediumUrl;

  const Photo({
    required this.id,
    required this.userId,
    this.uploadedBy,
    required this.fileHash,
    required this.fileSize,
    required this.mimeType,
    this.width,
    this.height,
    this.takenAt,
    this.latitude,
    this.longitude,
    this.locationName,
    this.cameraMake,
    this.cameraModel,
    this.description,
    required this.isFavorite,
    required this.isVideo,
    this.duration,
    required this.createdAt,
    required this.thumbSmallUrl,
    required this.thumbMediumUrl,
  });

  factory Photo.fromJson(Map<String, dynamic> json, {String serverUrl = ''}) {
    return Photo(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      uploadedBy: json['uploaded_by'] as String?,
      fileHash: json['file_hash'] as String,
      fileSize: json['file_size'] as int,
      mimeType: json['mime_type'] as String,
      width: json['width'] as int?,
      height: json['height'] as int?,
      takenAt: json['taken_at'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      locationName: json['location_name'] as String?,
      cameraMake: json['camera_make'] as String?,
      cameraModel: json['camera_model'] as String?,
      description: json['description'] as String?,
      isFavorite: json['is_favorite'] as bool? ?? false,
      isVideo: json['is_video'] as bool? ?? false,
      duration: (json['duration'] as num?)?.toDouble(),
      createdAt: json['created_at'] as String,
      thumbSmallUrl: '$serverUrl${json['thumb_small_url']}',
      thumbMediumUrl: '$serverUrl${json['thumb_medium_url']}',
    );
  }

  /// Parse takenAt or createdAt into a DateTime for grouping.
  DateTime get displayDate {
    final src = takenAt ?? createdAt;
    return DateTime.tryParse(src) ?? DateTime.now();
  }
}

class PhotoList {
  final List<Photo> photos;
  final String? nextCursor;
  final int totalCount;

  const PhotoList({
    required this.photos,
    this.nextCursor,
    required this.totalCount,
  });

  factory PhotoList.fromJson(Map<String, dynamic> json, {String serverUrl = ''}) {
    return PhotoList(
      photos: (json['photos'] as List).map((e) => Photo.fromJson(e, serverUrl: serverUrl)).toList(),
      nextCursor: json['next_cursor'] as String?,
      totalCount: json['total_count'] as int,
    );
  }
}
