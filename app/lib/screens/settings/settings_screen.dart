import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';

/// Settings screen for selecting backup folders and viewing backup stats.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  List<AssetPathEntity> _albums = [];
  Map<String, int> _albumCounts = {};
  Set<String> _selected = {};
  bool _loading = true;

  // Server stats
  int _serverPhotoCount = 0;
  String _serverTotalSize = '';
  String _serverStorageInfo = '';
  double _serverUsagePercent = 0;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
    _loadServerStats();
  }

  Future<void> _loadAlbums() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진 접근 권한이 필요합니다')),
        );
        Navigator.pop(context);
      }
      return;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
    );

    final counts = <String, int>{};
    for (final album in albums) {
      counts[album.id] = await album.assetCountAsync;
    }

    // Load previously selected albums
    final settings = ref.read(settingsProvider);
    final selectedSet = <String>{};
    for (final id in settings.selectedAlbumIds) {
      if (albums.any((a) => a.id == id)) {
        selectedSet.add(id);
      }
    }

    if (mounted) {
      setState(() {
        _albums = albums;
        _albumCounts = counts;
        _selected = selectedSet;
        _loading = false;
      });
    }
  }

  Future<void> _loadServerStats() async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.get('/system/status');
      final data = resp.data;
      if (mounted) {
        setState(() {
          _serverPhotoCount = data['photo_count'] ?? 0;
          _serverTotalSize = _formatBytes(data['total_size_bytes'] ?? 0);
          final storage = data['storage'] as Map<String, dynamic>?;
          if (storage != null) {
            final total = _formatBytes(storage['total_bytes'] ?? 0);
            final used = _formatBytes(storage['used_bytes'] ?? 0);
            _serverUsagePercent =
                (storage['usage_percent'] as num?)?.toDouble() ?? 0;
            _serverStorageInfo = '$used / $total';
          }
        });
      }
    } catch (_) {}
  }

  String _formatBytes(dynamic bytes) {
    final b = (bytes is int) ? bytes : (bytes as num).toInt();
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _save() async {
    final names = <String, String>{};
    for (final album in _albums) {
      if (_selected.contains(album.id)) {
        names[album.id] = album.name;
      }
    }
    await ref.read(settingsProvider.notifier).save(
          _selected.toList(),
          names,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장되었습니다')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('백업 설정'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('저장'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Server backup summary card
                _buildStatsCard(theme),
                const Divider(),

                // Auto-backup toggle
                SwitchListTile(
                  title: const Text('WiFi 자동 백업'),
                  subtitle:
                      const Text('같은 네트워크의 서버에 연결되면 자동으로 백업합니다'),
                  value: settings.autoBackupEnabled,
                  onChanged: (val) {
                    ref.read(settingsProvider.notifier).setAutoBackup(val);
                  },
                  secondary: const Icon(Icons.wifi),
                ),
                const Divider(),

                // Album selection header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '백업할 앨범을 선택하세요.\n선택하지 않으면 수동 업로드만 가능합니다.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selected = _albums.map((a) => a.id).toSet();
                          });
                        },
                        child: const Text('전체 선택'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          setState(() => _selected.clear());
                        },
                        child: const Text('선택 해제'),
                      ),
                    ],
                  ),
                ),
                const Divider(),

                // Album list with backup stats
                ..._albums.map((album) {
                  final count = _albumCounts[album.id] ?? 0;
                  final isSelected = _selected.contains(album.id);

                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selected.add(album.id);
                        } else {
                          _selected.remove(album.id);
                        }
                      });
                    },
                    title: Text(album.name),
                    subtitle: Text('$count 장'),
                    secondary: const Icon(Icons.photo_album_outlined),
                  );
                }),

                // Server storage info
                if (_serverStorageInfo.isNotEmpty) ...[
                  const Divider(),
                  _buildServerStorageCard(theme),
                ],

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildStatsCard(ThemeData theme) {
    final syncCache = ref.read(syncCacheProvider);
    final totalSynced = syncCache.syncedCount;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('전체 백업 현황',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.cloud_done, size: 48, color: Colors.blue.shade300),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('백업 완료: $totalSynced 장'),
                      Text('서버 사진: $_serverPhotoCount 장 ($_serverTotalSize)'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerStorageCard(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage, size: 20, color: Colors.grey),
              const SizedBox(width: 8),
              Text('서버 저장공간', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _serverUsagePercent / 100,
              backgroundColor: Colors.grey[200],
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$_serverStorageInfo (${_serverUsagePercent.toStringAsFixed(1)}% 사용)',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
