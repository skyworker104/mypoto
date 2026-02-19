import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:photo_manager/photo_manager.dart';
import '../config/app_config.dart';
import 'api_client.dart';
import 'backup_log_service.dart';
import 'notification_service.dart';
import 'sync_cache.dart';

/// Backup state enum.
enum BackupState { idle, scanning, uploading, paused, complete, error }

/// Progress info for UI.
class BackupProgress {
  final BackupState state;
  final int totalPhotos;
  final int uploadedPhotos;
  final int skippedPhotos;
  final int failedPhotos;
  final String? currentFile;
  final String? errorMessage;

  const BackupProgress({
    this.state = BackupState.idle,
    this.totalPhotos = 0,
    this.uploadedPhotos = 0,
    this.skippedPhotos = 0,
    this.failedPhotos = 0,
    this.currentFile,
    this.errorMessage,
  });

  double get percent =>
      totalPhotos > 0 ? (uploadedPhotos + skippedPhotos + failedPhotos) / totalPhotos : 0;
}

/// Photo/video backup service.
/// Scans device gallery, checks local sync cache first to skip
/// already-backed-up files, then batch-checks server for remaining,
/// and uploads new files with retry, logging, and notifications.
class BackupService {
  final ApiClient _api;
  final SyncStateCache _syncCache;
  final BackupLogService _log;
  final _progressController = StreamController<BackupProgress>.broadcast();
  BackupProgress _progress = const BackupProgress();
  bool _cancelled = false;

  BackupService(this._api, this._syncCache, this._log);

  Stream<BackupProgress> get progressStream => _progressController.stream;
  BackupProgress get progress => _progress;

  /// Request photo library permission.
  Future<bool> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state.isAuth;
  }

  /// Start full backup process.
  Future<void> startBackup({List<String>? albumFilter}) async {
    _cancelled = false;
    _emit(const BackupProgress(state: BackupState.scanning));

    // 1. Get all photos + videos from device
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
    );
    if (albums.isEmpty) {
      _emit(const BackupProgress(state: BackupState.complete));
      return;
    }

    final targetAlbums = albumFilter != null && albumFilter.isNotEmpty
        ? albums.where((a) => albumFilter.contains(a.id)).toList()
        : albums;

    if (targetAlbums.isEmpty) {
      _emit(const BackupProgress(state: BackupState.complete));
      return;
    }

    // Collect all assets
    List<AssetEntity> allAssets = [];
    for (final album in targetAlbums) {
      final count = await album.assetCountAsync;
      final assets = await album.getAssetListRange(start: 0, end: count);
      allAssets.addAll(assets);
    }

    // Deduplicate by ID
    final seen = <String>{};
    allAssets = allAssets.where((a) => seen.add(a.id)).toList();

    // 2. Skip already-synced assets using local cache (no server call)
    await _syncCache.load();
    final unsyncedAssets = <AssetEntity>[];
    int localSkipped = 0;
    for (final asset in allAssets) {
      if (_syncCache.isAssetSynced(asset.id)) {
        localSkipped++;
      } else {
        unsyncedAssets.add(asset);
      }
    }

    _emit(BackupProgress(
      state: BackupState.uploading,
      totalPhotos: allAssets.length,
      skippedPhotos: localSkipped,
    ));

    NotificationService.showProgress(
      current: localSkipped,
      total: allAssets.length,
    );

    // 3. Process unsynced assets in batches
    int uploaded = 0;
    int skipped = localSkipped;
    int failed = 0;

    for (var i = 0; i < unsyncedAssets.length; i += AppConfig.batchCheckSize) {
      if (_cancelled) break;

      final batch = unsyncedAssets.sublist(
        i,
        (i + AppConfig.batchCheckSize).clamp(0, unsyncedAssets.length),
      );

      // Compute hashes for batch
      final hashMap = <String, AssetEntity>{};
      for (final asset in batch) {
        final file = await asset.file;
        if (file == null) continue;
        final bytes = await file.readAsBytes();
        final hash = sha256.convert(bytes).toString();
        hashMap[hash] = asset;
        _syncCache.addLocalHash(asset.id, hash);
      }

      // Check server for remaining duplicates
      try {
        final resp = await _api.post('/photos/check', data: {
          'hashes': hashMap.keys.toList(),
        });
        final existing = Set<String>.from(resp.data['existing'] ?? []);
        final newHashes = hashMap.keys.where((h) => !existing.contains(h));

        _syncCache.markExistingHashes(existing);
        skipped += existing.length;

        // Upload new files
        for (final hash in newHashes) {
          if (_cancelled) break;
          final asset = hashMap[hash]!;
          final file = await asset.file;
          if (file == null) continue;

          final isVideo = asset.type == AssetType.video;
          final filename = asset.title ?? (isVideo ? 'video' : 'photo');

          _emit(BackupProgress(
            state: BackupState.uploading,
            totalPhotos: allAssets.length,
            uploadedPhotos: uploaded,
            skippedPhotos: skipped,
            failedPhotos: failed,
            currentFile: filename,
          ));

          NotificationService.showProgress(
            current: uploaded + skipped + failed,
            total: allAssets.length,
            filename: filename,
          );

          bool success = false;
          for (var retry = 0; retry < AppConfig.maxRetries; retry++) {
            try {
              final uploadResp = await _api.upload('/photos/upload',
                  file: file, fields: {'hash': hash});
              uploaded++;
              final photoId = uploadResp.data['photo_id'] as String?;
              if (photoId != null) {
                _syncCache.addMapping(hash, photoId);
              }
              success = true;
              break;
            } catch (e) {
              if (retry == AppConfig.maxRetries - 1) {
                failed++;
                await _log.logError('업로드 실패: $e', filename: filename);
              }
              await Future.delayed(Duration(seconds: retry + 1));
            }
          }
          if (!success) {
            // Already logged above
          }
        }
      } catch (e) {
        await _log.logError('배치 처리 오류: $e');
        _emit(BackupProgress(
          state: BackupState.error,
          totalPhotos: allAssets.length,
          uploadedPhotos: uploaded,
          skippedPhotos: skipped,
          failedPhotos: failed,
          errorMessage: e.toString(),
        ));
        NotificationService.showError('백업 오류: $e');
        return;
      }
    }

    await _syncCache.save();
    await _log.logSummary(uploaded, skipped - localSkipped, failed);

    final finalState = _cancelled ? BackupState.paused : BackupState.complete;
    _emit(BackupProgress(
      state: finalState,
      totalPhotos: allAssets.length,
      uploadedPhotos: uploaded,
      skippedPhotos: skipped,
      failedPhotos: failed,
    ));

    if (!_cancelled) {
      NotificationService.showComplete(
        uploaded: uploaded,
        skipped: skipped,
        failed: failed,
      );
    }
  }

  /// Upload specific assets (for manual upload).
  Future<void> uploadAssets(List<AssetEntity> assets) async {
    _cancelled = false;
    _emit(BackupProgress(
      state: BackupState.uploading,
      totalPhotos: assets.length,
    ));

    int uploaded = 0;
    int skipped = 0;
    int failed = 0;

    for (var i = 0; i < assets.length; i += AppConfig.batchCheckSize) {
      if (_cancelled) break;

      final batch = assets.sublist(
        i,
        (i + AppConfig.batchCheckSize).clamp(0, assets.length),
      );

      final hashMap = <String, AssetEntity>{};
      for (final asset in batch) {
        final file = await asset.file;
        if (file == null) continue;
        final bytes = await file.readAsBytes();
        final hash = sha256.convert(bytes).toString();
        hashMap[hash] = asset;
        _syncCache.addLocalHash(asset.id, hash);
      }

      try {
        final resp = await _api.post('/photos/check', data: {
          'hashes': hashMap.keys.toList(),
        });
        final existing = Set<String>.from(resp.data['existing'] ?? []);
        final newHashes = hashMap.keys.where((h) => !existing.contains(h));
        _syncCache.markExistingHashes(existing);
        skipped += existing.length;

        for (final hash in newHashes) {
          if (_cancelled) break;
          final asset = hashMap[hash]!;
          final file = await asset.file;
          if (file == null) continue;

          final filename = asset.title ?? (asset.type == AssetType.video ? 'video' : 'photo');

          _emit(BackupProgress(
            state: BackupState.uploading,
            totalPhotos: assets.length,
            uploadedPhotos: uploaded,
            skippedPhotos: skipped,
            failedPhotos: failed,
            currentFile: filename,
          ));

          for (var retry = 0; retry < AppConfig.maxRetries; retry++) {
            try {
              final uploadResp = await _api.upload('/photos/upload',
                  file: file, fields: {'hash': hash});
              uploaded++;
              final photoId = uploadResp.data['photo_id'] as String?;
              if (photoId != null) {
                _syncCache.addMapping(hash, photoId);
              }
              break;
            } catch (e) {
              if (retry == AppConfig.maxRetries - 1) {
                failed++;
                await _log.logError('업로드 실패: $e', filename: filename);
              }
              await Future.delayed(Duration(seconds: retry + 1));
            }
          }
        }
      } catch (e) {
        await _log.logError('배치 처리 오류: $e');
        _emit(BackupProgress(
          state: BackupState.error,
          totalPhotos: assets.length,
          uploadedPhotos: uploaded,
          skippedPhotos: skipped,
          failedPhotos: failed,
          errorMessage: e.toString(),
        ));
        return;
      }
    }

    await _syncCache.save();
    await _log.logSummary(uploaded, skipped, failed);

    _emit(BackupProgress(
      state: _cancelled ? BackupState.paused : BackupState.complete,
      totalPhotos: assets.length,
      uploadedPhotos: uploaded,
      skippedPhotos: skipped,
      failedPhotos: failed,
    ));
  }

  void pause() => _cancelled = true;

  void _emit(BackupProgress p) {
    _progress = p;
    _progressController.add(p);
  }

  void dispose() {
    _cancelled = true;
    _progressController.close();
  }
}
