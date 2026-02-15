import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

class HighlightItem {
  final String id;
  final String title;
  final String? description;
  final String sourceType;
  final String status;
  final int? durationSeconds;
  final int photoCount;
  final String? dateFrom;
  final String? dateTo;
  final bool hasVideo;
  final String? thumbnailUrl;
  final String? createdAt;
  final String? completedAt;
  final String? errorMessage;

  HighlightItem({
    required this.id,
    required this.title,
    this.description,
    required this.sourceType,
    required this.status,
    this.durationSeconds,
    this.photoCount = 0,
    this.dateFrom,
    this.dateTo,
    this.hasVideo = false,
    this.thumbnailUrl,
    this.createdAt,
    this.completedAt,
    this.errorMessage,
  });

  factory HighlightItem.fromJson(Map<String, dynamic> json) {
    return HighlightItem(
      id: json['id'],
      title: json['title'] ?? '',
      description: json['description'],
      sourceType: json['source_type'] ?? 'date_range',
      status: json['status'] ?? 'pending',
      durationSeconds: json['duration_seconds'],
      photoCount: json['photo_count'] ?? 0,
      dateFrom: json['date_from'],
      dateTo: json['date_to'],
      hasVideo: json['has_video'] ?? false,
      thumbnailUrl: json['thumbnail_url'],
      createdAt: json['created_at'],
      completedAt: json['completed_at'],
      errorMessage: json['error_message'],
    );
  }

  String get durationText {
    if (durationSeconds == null) return '';
    final m = durationSeconds! ~/ 60;
    final s = durationSeconds! % 60;
    return '$m분 $s초';
  }

  String get statusText {
    switch (status) {
      case 'pending':
        return '대기중';
      case 'processing':
        return '생성중...';
      case 'completed':
        return '완료';
      case 'failed':
        return '실패';
      default:
        return status;
    }
  }
}

final highlightsProvider =
    FutureProvider<List<HighlightItem>>((ref) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get('/highlights');
  return (resp.data['highlights'] as List)
      .map((j) => HighlightItem.fromJson(j))
      .toList();
});
