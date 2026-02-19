import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notification service for backup progress and completion.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'photonest_backup';
  static const _channelName = 'PhotoNest 백업';
  static const _progressId = 1;
  static const _completeId = 2;

  /// Initialize notification plugin.
  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);
  }

  /// Request notification permission (Android 13+).
  static Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(alert: true, badge: true);
      return granted ?? false;
    }
    return false;
  }

  /// Show backup progress notification.
  static Future<void> showProgress({
    required int current,
    required int total,
    String? filename,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '사진 백업 진행 상태',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: total,
      progress: current,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
    );
    final details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      _progressId,
      'PhotoNest 백업 중',
      '$current / $total ${filename ?? ""}',
      details,
    );
  }

  /// Show backup complete notification.
  static Future<void> showComplete({
    required int uploaded,
    required int skipped,
    int failed = 0,
  }) async {
    // Cancel progress notification
    await _plugin.cancel(_progressId);

    final body = '$uploaded장 업로드, $skipped장 건너뜀'
        '${failed > 0 ? ', $failed장 실패' : ''}';

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '사진 백업 진행 상태',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(_completeId, '백업 완료', body, details);
  }

  /// Show backup error notification.
  static Future<void> showError(String message) async {
    await _plugin.cancel(_progressId);

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '사진 백업 진행 상태',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(_completeId, '백업 오류', message, details);
  }

  /// Cancel all backup notifications.
  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
