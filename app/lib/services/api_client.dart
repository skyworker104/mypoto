import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

/// HTTP client with JWT auto-attach and token refresh.
class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _baseUrl;
  String? _accessToken;
  String? _refreshToken;
  String? _deviceId;

  ApiClient() {
    _dio = Dio(BaseOptions(
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));
  }

  // --- Configuration ---

  Future<void> configure({
    required String baseUrl,
    String? accessToken,
    String? refreshToken,
    String? deviceId,
  }) async {
    _baseUrl = '$baseUrl${AppConfig.apiPrefix}';
    _dio.options.baseUrl = _baseUrl!;
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _deviceId = deviceId;

    if (accessToken != null) {
      await _storage.write(key: 'access_token', value: accessToken);
    }
    if (refreshToken != null) {
      await _storage.write(key: 'refresh_token', value: refreshToken);
    }
    if (deviceId != null) {
      await _storage.write(key: 'device_id', value: deviceId);
    }
    if (baseUrl.isNotEmpty) {
      await _storage.write(key: 'base_url', value: baseUrl);
    }
  }

  Future<bool> restoreSession() async {
    try {
      final baseUrl = await _storage.read(key: 'base_url')
          .timeout(const Duration(seconds: 2));
      final accessToken = await _storage.read(key: 'access_token')
          .timeout(const Duration(seconds: 2));
      final refreshToken = await _storage.read(key: 'refresh_token')
          .timeout(const Duration(seconds: 2));
      final deviceId = await _storage.read(key: 'device_id')
          .timeout(const Duration(seconds: 2));

      if (baseUrl == null || accessToken == null) return false;

      await configure(
        baseUrl: baseUrl,
        accessToken: accessToken,
        refreshToken: refreshToken,
        deviceId: deviceId,
      );
      return true;
    } catch (_) {
      // SecureStorage failure (e.g. Keystore issue after reinstall)
      return false;
    }
  }

  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _deviceId = null;
    await _storage.deleteAll();
  }

  // --- Interceptors ---

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_accessToken != null) {
      options.headers['Authorization'] = 'Bearer $_accessToken';
    }
    handler.next(options);
  }

  Future<void> _onError(
      DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && _refreshToken != null) {
      try {
        final newToken = await _refreshAccessToken();
        if (newToken != null) {
          _accessToken = newToken;
          await _storage.write(key: 'access_token', value: newToken);

          // Retry original request
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 'Bearer $newToken';
          final response = await _dio.fetch(opts);
          return handler.resolve(response);
        }
      } catch (_) {}
    }
    handler.next(err);
  }

  Future<String?> _refreshAccessToken() async {
    if (_refreshToken == null || _deviceId == null) return null;
    try {
      final response = await _dio.post(
        '/auth/refresh',
        data: {
          'refresh_token': _refreshToken,
          'device_id': _deviceId,
        },
        options: Options(headers: {}), // No auth header for refresh
      );
      return response.data['access_token'] as String?;
    } catch (_) {
      return null;
    }
  }

  // --- HTTP Methods ---

  Future<Response> get(String path,
      {Map<String, dynamic>? queryParams}) async {
    return _dio.get(path, queryParameters: queryParams);
  }

  Future<Response> post(String path, {dynamic data}) async {
    return _dio.post(path, data: data);
  }

  Future<Response> patch(String path, {dynamic data}) async {
    return _dio.patch(path, data: data);
  }

  Future<Response> delete(String path) async {
    return _dio.delete(path);
  }

  Future<Response> upload(String path,
      {required File file,
      Map<String, dynamic>? fields,
      void Function(int, int)? onProgress}) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path,
          filename: file.path.split('/').last),
      if (fields != null) ...fields,
    });
    return _dio.post(path, data: formData,
        onSendProgress: onProgress);
  }

  Dio get dio => _dio;
  String? get baseUrl => _baseUrl;
  String? get accessToken => _accessToken;
  bool get isAuthenticated => _accessToken != null;
}
