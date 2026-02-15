import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:photo_manager/photo_manager.dart';
import '../config/app_config.dart';
import 'api_client.dart';
import 'sync_cache.dart';

/// Backup state enum.
enum BackupState { idle, scanning, uploading, paused, complete, error }

/// Progress info for UI.
class BackupProgress {
  final BackupState state;
  final int totalPhotos;
  final int uploadedPhotos;
  final int skippedPhotos;
  final String? currentFile;
  final String? errorMessage;

  const BackupProgress({
    this.state = BackupState.idle,
    this.totalPhotos = 0,
    this.uploadedPhotos = 0,
    this.skippedPhotos = 0,
    this.currentFile,
    this.errorMessage,
  });

  double get percent =>
      totalPhotos > 0 ? (uploadedPhotos + skippedPhotos) / totalPhotos : 0;
}

/// Automatic photo backup service.
/// Scans device gallery, checks for duplicates, uploads new photos.
class BackupService {
  final ApiClient _api;
  final SyncStateCache _syncCache;
  final _progressController = StreamController<BackupProgress>.broadcast();
  BackupProgress _progress = const BackupProgress();
  bool _cancelled = false;

  BackupService(this._api, this._syncCache);

  Stream<BackupProgress> get progressStream => _progressController.stream;
  BackupProgress get progress => _progress;

  /// Request photo library permission.
  Future<bool> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state.isAuth;
  }

  /// Start full backup process.
  /// If [albumFilter] is provided, only scan those album IDs.
  Future<void> startBackup({List<String>? albumFilter}) async {
    _cancelled = false;
    _emit(const BackupProgress(state: BackupState.scanning));

    // 1. Get all photos from device
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common, // photos + videos
    );
    if (albums.isEmpty) {
      _emit(const BackupProgress(state: BackupState.complete));
      return;
    }

    // Filter albums if specified
    final targetAlbums = albumFilter != null && albumFilter.isNotEmpty
        ? albums.where((a) => albumFilter.contains(a.id)).toList()
        : albums;

    if (targetAlbums.isEmpty) {
      _emit(const BackupProgress(state: BackupState.complete));
      return;
    }

    // Get all assets
    List<AssetEntity> allAssets = [];
    for (final album in targetAlbums) {
      final count = await album.assetCountAsync;
      final assets = await album.getAssetListRange(start: 0, end: count);
      allAssets.addAll(assets);
    }

    // Deduplicate by ID
    final seen = <String>{};
    allAssets = allAssets.where((a) => seen.add(a.id)).toList();

    _emit(BackupProgress(
      state: BackupState.uploading,
      totalPhotos: allAssets.length,
    ));

    // 2. Check duplicates in batches
    int uploaded = 0;
    int skipped = 0;

    for (var i = 0; i < allAssets.length; i += AppConfig.batchCheckSize) {
      if (_cancelled) break;

      final batch = allAssets.sublist(
        i,
        (i + AppConfig.batchCheckSize).clamp(0, allAssets.length),
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

      // Check which already exist on server
      try {
        final resp = await _api.post('/photos/check', data: {
          'hashes': hashMap.keys.toList(),
        });
        final existing = Set<String>.from(resp.data['existing'] ?? []);
        final newHashes = hashMap.keys.where((h) => !existing.contains(h));

        // Update sync cache with existing hashes
        _syncCache.markExistingHashes(existing);

        skipped += existing.length;

        // 3. Upload new photos
        for (final hash in newHashes) {
          if (_cancelled) break;
          final asset = hashMap[hash]!;
          final file = await asset.file;
          if (file == null) continue;

          _emit(BackupProgress(
            state: BackupState.uploading,
            totalPhotos: allAssets.length,
            uploadedPhotos: uploaded,
            skippedPhotos: skipped,
            currentFile: asset.title ?? 'photo',
          ));

          // Upload with retry
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
                // Skip this file after max retries
              }
              await Future.delayed(Duration(seconds: retry + 1));
            }
          }
        }
      } catch (e) {
        _emit(BackupProgress(
          state: BackupState.error,
          totalPhotos: allAssets.length,
          uploadedPhotos: uploaded,
          skippedPhotos: skipped,
          errorMessage: e.toString(),
        ));
        return;
      }
    }

    await _syncCache.save();

    _emit(BackupProgress(
      state: _cancelled ? BackupState.paused : BackupState.complete,
      totalPhotos: allAssets.length,
      uploadedPhotos: uploaded,
      skippedPhotos: skipped,
    ));
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

          _emit(BackupProgress(
            state: BackupState.uploading,
            totalPhotos: assets.length,
            uploadedPhotos: uploaded,
            skippedPhotos: skipped,
            currentFile: asset.title ?? 'photo',
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
              if (retry == AppConfig.maxRetries - 1) break;
              await Future.delayed(Duration(seconds: retry + 1));
            }
          }
        }
      } catch (e) {
        _emit(BackupProgress(
          state: BackupState.error,
          totalPhotos: assets.length,
          uploadedPhotos: uploaded,
          skippedPhotos: skipped,
          errorMessage: e.toString(),
        ));
        return;
      }
    }

    await _syncCache.save();

    _emit(BackupProgress(
      state: _cancelled ? BackupState.paused : BackupState.complete,
      totalPhotos: assets.length,
      uploadedPhotos: uploaded,
      skippedPhotos: skipped,
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
