/// App-wide configuration constants.
class AppConfig {
  static const String appName = 'PhotoNest';
  static const String appVersion = '0.1.0';

  // API
  static const int defaultPort = 8080;
  static const String apiPrefix = '/api/v1';
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Thumbnails
  static const int gridColumnsDefault = 4;
  static const int gridColumnsMin = 3;
  static const int gridColumnsMax = 7;

  // Backup
  static const int maxConcurrentUploads = 3;
  static const int maxRetries = 3;
  static const int batchCheckSize = 100;

  // Cache
  static const int thumbnailCacheMaxCount = 500;
  static const Duration tokenRefreshThreshold = Duration(minutes: 5);
}
