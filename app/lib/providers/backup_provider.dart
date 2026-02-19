import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/backup_log_service.dart';
import '../services/backup_service.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';

final backupLogProvider = Provider<BackupLogService>((ref) {
  final log = BackupLogService();
  log.load();
  return log;
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    ref.read(apiClientProvider),
    ref.read(syncCacheProvider),
    ref.read(backupLogProvider),
  );
});

final backupProgressProvider = StreamProvider<BackupProgress>((ref) {
  return ref.read(backupServiceProvider).progressStream;
});
