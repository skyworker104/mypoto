import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
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
          final totalBytes = data['storage_total_bytes'];
          final usedBytes = data['storage_used_bytes'];
          if (totalBytes != null) {
            final total = _formatBytes(totalBytes);
            final used = _formatBytes(usedBytes ?? 0);
            _serverUsagePercent =
                (data['storage_usage_percent'] as num?)?.toDouble() ?? 0;
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

                // Backup log
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('백업 로그'),
                  subtitle: const Text('업로드 성공/실패 상세 기록'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/backup-log'),
                ),

                // Server storage info
                if (_serverStorageInfo.isNotEmpty) ...[
                  const Divider(),
                  _buildServerStorageCard(theme),
                ],

                // Server connection settings
                const Divider(),
                _buildServerConnectionSection(theme),

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

  Widget _buildServerConnectionSection(ThemeData theme) {
    final connectivity = ref.watch(connectivityProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(
            connectivity.isServerReachable ? Icons.wifi : Icons.wifi_off,
            color: connectivity.isServerReachable ? Colors.green : Colors.orange,
          ),
          title: const Text('서버 연결 상태'),
          subtitle: Text(
            connectivity.isServerReachable
                ? '연결됨'
                : connectivity.isWiFi
                    ? '서버와 같은 WiFi 존이 아닙니다'
                    : 'WiFi에 연결되어 있지 않습니다',
          ),
          trailing: TextButton(
            onPressed: () {
              ref.read(connectivityProvider.notifier).checkNow();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('서버 연결 확인 중...')),
              );
            },
            child: const Text('재연결'),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: const Text('서버 재설정'),
          subtitle: const Text('다른 서버에 연결하거나 IP를 변경합니다'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showReconnectDialog(),
        ),
      ],
    );
  }

  void _showReconnectDialog() {
    final controller = TextEditingController();
    final api = ref.read(apiClientProvider);
    final currentUrl = (api.baseUrl ?? '').replaceAll('/api/v1', '');
    controller.text = currentUrl.replaceAll('http://', '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('서버 재설정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('서버 IP를 입력하세요.\n포트는 자동으로 8080이 적용됩니다.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '서버 IP',
                hintText: '예: 192.168.0.10',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              var input = controller.text.trim();
              if (input.isEmpty) return;

              // Strip protocol/port if user typed full URL
              input = input
                  .replaceAll('http://', '')
                  .replaceAll('https://', '');
              if (input.contains(':')) {
                input = input.split(':').first;
              }
              if (input.contains('/')) {
                input = input.split('/').first;
              }

              final newUrl = 'http://$input:8080';
              await ref
                  .read(connectivityProvider.notifier)
                  .reconnect(newUrl);

              // Update stored base URL
              const storage = FlutterSecureStorage();
              await storage.write(key: 'base_url', value: '$newUrl/api/v1');

              if (mounted) {
                // Force full restart by navigating to discover
                context.go('/discover');
              }
            },
            child: const Text('연결'),
          ),
        ],
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
