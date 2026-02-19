import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../providers/auth_provider.dart';
import '../../providers/backup_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/local_photo_provider.dart';
import '../../providers/photo_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/backup_service.dart';
import '../../services/connectivity_service.dart';
import '../../widgets/photo_grid.dart';
import '../settings/photo_picker_screen.dart';

/// Photos tab - timeline view with date-grouped grid.
/// Supports online (server photos) and offline (local photos) modes.
class PhotosTab extends ConsumerStatefulWidget {
  const PhotosTab({super.key});

  @override
  ConsumerState<PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends ConsumerState<PhotosTab> {
  StreamSubscription? _connectivitySub;
  bool _autoBackupTriggered = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(photoTimelineProvider.notifier).loadInitial();
      // Load local photos for offline mode
      ref.read(localPhotoProvider.notifier).load();
      // Start connectivity monitoring
      _startConnectivityMonitoring();
    });
  }

  void _startConnectivityMonitoring() {
    final connectivity = ref.read(connectivityProvider.notifier);
    _connectivitySub = connectivity.service.stream.listen((state) {
      _handleConnectivityChange(state);
    });
  }

  void _handleConnectivityChange(ServerConnectivityState state) {
    // Auto-backup when WiFi + server reachable
    if (state.isWiFi && state.isServerReachable && !_autoBackupTriggered) {
      final settings = ref.read(settingsProvider);
      if (settings.autoBackupEnabled && settings.hasSelection) {
        _autoBackupTriggered = true;
        // Debounce: wait 5 seconds before triggering
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            _triggerAutoBackup();
          }
        });
      }
    }
    if (!state.isServerReachable) {
      _autoBackupTriggered = false;
    }
  }

  void _triggerAutoBackup() {
    final settings = ref.read(settingsProvider);
    if (!settings.autoBackupEnabled || !settings.hasSelection) return;
    final backup = ref.read(backupServiceProvider);
    backup.startBackup(albumFilter: settings.selectedAlbumIds);
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = ref.watch(connectivityProvider);
    final isOnline = connectivity.isServerReachable;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('PhotoNest'),
            const SizedBox(width: 8),
            Icon(
              isOnline ? Icons.cloud_done : Icons.cloud_off,
              size: 16,
              color: isOnline ? Colors.green : Colors.orange,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined),
            onPressed: () {
              final settings = ref.read(settingsProvider);
              if (settings.hasSelection) {
                _startBackup(context);
              } else {
                _manualUpload(context);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: isOnline ? _buildOnlineView() : _buildOfflineView(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _takePhoto(context),
        child: const Icon(Icons.camera_alt),
      ),
    );
  }

  Widget _buildOnlineView() {
    final state = ref.watch(photoTimelineProvider);

    if (state.photos.isEmpty && state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.photos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('아직 백업된 사진이 없습니다',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return PhotoGrid(
      photos: state.photos,
      httpHeaders: {
        if (ref.read(apiClientProvider).accessToken != null)
          'Authorization':
              'Bearer ${ref.read(apiClientProvider).accessToken}',
      },
      syncStatusMap: _buildSyncStatusMap(state.photos),
      onPhotoTap: (photo) => context.push('/photo/${photo.id}'),
      onLoadMore: () {
        ref.read(photoTimelineProvider.notifier).loadMore();
      },
      isLoadingMore: state.isLoading,
    );
  }

  Map<String, SyncStatus> _buildSyncStatusMap(List photos) {
    // All server photos are by definition "synced" (they're on server)
    // We mark them as synced to show the cloud_done icon
    final map = <String, SyncStatus>{};
    for (final photo in photos) {
      map[photo.id] = SyncStatus.synced;
    }
    return map;
  }

  Widget _buildOfflineView() {
    final localState = ref.watch(localPhotoProvider);
    final syncCache = ref.read(syncCacheProvider);

    return Column(
      children: [
        // Offline banner
        Container(
          width: double.infinity,
          color: Colors.orange.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.cloud_off, size: 18, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Text(
                '오프라인 모드 - 기기 사진만 표시됩니다',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: localState.photos.isEmpty && localState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : localState.photos.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.photo_library_outlined,
                              size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('기기에 사진이 없습니다',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 16)),
                        ],
                      ),
                    )
                  : LocalPhotoGrid(
                      photos: localState.photos,
                      onLoadMore: () {
                        ref.read(localPhotoProvider.notifier).loadMore();
                      },
                      isLoadingMore: localState.isLoading,
                      isAssetSynced: (assetId) =>
                          syncCache.isAssetSynced(assetId),
                    ),
        ),
      ],
    );
  }

  // --- Camera ---

  AssetPathEntity? _photoNestAlbum;

  Future<void> _takePhoto(BuildContext context) async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
    );
    if (xFile == null) return;

    try {
      // Save to device gallery
      final bytes = await xFile.readAsBytes();
      final filename = 'PhotoNest_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final asset = await PhotoManager.editor.saveImage(
        bytes,
        title: filename,
        filename: filename,
      );

      // Ensure PhotoNest album exists and copy photo there
      await _ensurePhotoNestAlbum();
      if (_photoNestAlbum != null) {
        await PhotoManager.editor.copyAssetToPath(
          asset: asset,
          pathEntity: _photoNestAlbum!,
        );
      }

      // Upload immediately if server is reachable
      final connectivity = ref.read(connectivityProvider);
      if (connectivity.isServerReachable) {
        final backup = ref.read(backupServiceProvider);
        await backup.uploadAssets([asset]);
        ref.read(photoTimelineProvider.notifier).loadInitial();
      }

      // Refresh local photos
      ref.read(localPhotoProvider.notifier).load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진이 저장되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    }
  }

  Future<void> _ensurePhotoNestAlbum() async {
    if (_photoNestAlbum != null) return;

    final albums = await PhotoManager.getAssetPathList();
    for (final album in albums) {
      if (album.name == 'PhotoNest') {
        _photoNestAlbum = album;
        return;
      }
    }

    // Create PhotoNest album (iOS only — Android uses directory-based albums)
    if (Platform.isIOS || Platform.isMacOS) {
      _photoNestAlbum =
          await PhotoManager.editor.darwin.createAlbum('PhotoNest');
    }
    // On Android, skip album creation — photos go to default gallery

    // Auto-add to backup settings
    if (_photoNestAlbum != null) {
      final settings = ref.read(settingsProvider);
      if (!settings.selectedAlbumIds.contains(_photoNestAlbum!.id)) {
        ref.read(settingsProvider.notifier).save(
          [...settings.selectedAlbumIds, _photoNestAlbum!.id],
          {...settings.albumNames, _photoNestAlbum!.id: 'PhotoNest'},
        );
      }
    }
  }

  // --- Backup ---

  Future<void> _startBackup(BuildContext context) async {
    final backup = ref.read(backupServiceProvider);

    final permitted = await backup.requestPermission();
    if (!permitted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진 접근 권한이 필요합니다')),
        );
      }
      return;
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BackupDialog(
        backup: backup,
        onDone: () {
          ref.read(photoTimelineProvider.notifier).loadInitial();
        },
      ),
    );

    final settings = ref.read(settingsProvider);
    backup.startBackup(
      albumFilter: settings.hasSelection ? settings.selectedAlbumIds : null,
    );
  }

  Future<void> _manualUpload(BuildContext context) async {
    final backup = ref.read(backupServiceProvider);

    final permitted = await backup.requestPermission();
    if (!permitted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진 접근 권한이 필요합니다')),
        );
      }
      return;
    }

    if (!context.mounted) return;

    final result = await Navigator.of(context).push<List<AssetEntity>>(
      MaterialPageRoute(builder: (_) => const PhotoPickerScreen()),
    );

    if (result == null || result.isEmpty || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BackupDialog(
        backup: backup,
        onDone: () {
          ref.read(photoTimelineProvider.notifier).loadInitial();
        },
      ),
    );

    backup.uploadAssets(result);
  }
}

class _BackupDialog extends StatelessWidget {
  final BackupService backup;
  final VoidCallback onDone;

  const _BackupDialog({required this.backup, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('사진 백업'),
      content: StreamBuilder<BackupProgress>(
        stream: backup.progressStream,
        builder: (context, snapshot) {
          final p = snapshot.data ?? const BackupProgress();

          if (p.state == BackupState.complete) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 48),
                const SizedBox(height: 16),
                Text('완료! ${p.uploadedPhotos}장 업로드, ${p.skippedPhotos}장 건너뜀'),
              ],
            );
          }

          if (p.state == BackupState.error) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text('오류: ${p.errorMessage ?? "알 수 없는 오류"}'),
              ],
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: p.percent > 0 ? p.percent : null),
              const SizedBox(height: 16),
              Text(p.state == BackupState.scanning
                  ? '사진 검색 중...'
                  : '${p.uploadedPhotos + p.skippedPhotos} / ${p.totalPhotos}'),
              if (p.currentFile != null) ...[
                const SizedBox(height: 8),
                Text(p.currentFile!,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis),
              ],
            ],
          );
        },
      ),
      actions: [
        StreamBuilder<BackupProgress>(
          stream: backup.progressStream,
          builder: (context, snapshot) {
            final state = snapshot.data?.state ?? BackupState.idle;
            final isDone = state == BackupState.complete ||
                state == BackupState.error;
            return TextButton(
              onPressed: () {
                if (!isDone) backup.pause();
                onDone();
                Navigator.pop(context);
              },
              child: Text(isDone ? '확인' : '취소'),
            );
          },
        ),
      ],
    );
  }
}
