import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/backup_service.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    ref.read(apiClientProvider),
    ref.read(syncCacheProvider),
  );
});

final backupProgressProvider = StreamProvider<BackupProgress>((ref) {
  return ref.read(backupServiceProvider).progressStream;
});
