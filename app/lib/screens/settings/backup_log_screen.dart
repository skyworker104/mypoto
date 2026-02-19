import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/backup_provider.dart';
import '../../services/backup_log_service.dart';

/// Screen showing detailed backup log entries.
class BackupLogScreen extends ConsumerStatefulWidget {
  const BackupLogScreen({super.key});

  @override
  ConsumerState<BackupLogScreen> createState() => _BackupLogScreenState();
}

class _BackupLogScreenState extends ConsumerState<BackupLogScreen> {
  List<BackupLogEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final log = ref.read(backupLogProvider);
    await log.load();
    if (mounted) {
      setState(() {
        _entries = log.entries;
        _loading = false;
      });
    }
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그 삭제'),
        content: const Text('모든 백업 로그를 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(backupLogProvider).clear();
      setState(() => _entries = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('백업 로그'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearLogs,
              tooltip: '로그 삭제',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('백업 로그가 없습니다',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (_, i) => _buildLogTile(_entries[i]),
                ),
    );
  }

  Widget _buildLogTile(BackupLogEntry entry) {
    final icon = switch (entry.type) {
      'success' => const Icon(Icons.check_circle, color: Colors.green, size: 20),
      'error' => const Icon(Icons.error, color: Colors.red, size: 20),
      'skip' => const Icon(Icons.skip_next, color: Colors.orange, size: 20),
      _ => const Icon(Icons.info, color: Colors.blue, size: 20),
    };

    final dateStr = DateFormat('MM/dd HH:mm:ss').format(entry.timestamp);

    return ListTile(
      leading: icon,
      title: Text(
        entry.message,
        style: const TextStyle(fontSize: 14),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${entry.filename != null ? "${entry.filename} · " : ""}$dateStr',
        style: const TextStyle(fontSize: 12),
      ),
      dense: true,
    );
  }
}
