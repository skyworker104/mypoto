import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Single backup log entry.
class BackupLogEntry {
  final DateTime timestamp;
  final String type; // 'success', 'error', 'skip'
  final String message;
  final String? filename;

  const BackupLogEntry({
    required this.timestamp,
    required this.type,
    required this.message,
    this.filename,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'type': type,
        'message': message,
        if (filename != null) 'filename': filename,
      };

  factory BackupLogEntry.fromJson(Map<String, dynamic> json) {
    return BackupLogEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: json['type'] as String,
      message: json['message'] as String,
      filename: json['filename'] as String?,
    );
  }
}

/// Persistent backup log service.
/// Stores up to [maxEntries] log entries in SharedPreferences.
class BackupLogService {
  static const _key = 'backup_log';
  static const maxEntries = 500;

  List<BackupLogEntry> _entries = [];
  bool _loaded = false;

  List<BackupLogEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _entries = list.map((e) => BackupLogEntry.fromJson(e)).toList();
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }

  /// Add a log entry and persist.
  Future<void> add({
    required String type,
    required String message,
    String? filename,
  }) async {
    await load();
    _entries.insert(
      0,
      BackupLogEntry(
        timestamp: DateTime.now(),
        type: type,
        message: message,
        filename: filename,
      ),
    );
    // Trim to max entries
    if (_entries.length > maxEntries) {
      _entries = _entries.sublist(0, maxEntries);
    }
    await _save();
  }

  /// Log a successful upload.
  Future<void> logSuccess(String filename) async {
    await add(type: 'success', message: '업로드 완료', filename: filename);
  }

  /// Log a skipped file (already on server).
  Future<void> logSkip(String filename) async {
    await add(type: 'skip', message: '이미 백업됨 (건너뜀)', filename: filename);
  }

  /// Log an error.
  Future<void> logError(String message, {String? filename}) async {
    await add(type: 'error', message: message, filename: filename);
  }

  /// Log backup session summary.
  Future<void> logSummary(int uploaded, int skipped, int failed) async {
    await add(
      type: 'success',
      message: '백업 완료: $uploaded장 업로드, $skipped장 건너뜀${failed > 0 ? ', $failed장 실패' : ''}',
    );
  }

  /// Clear all logs.
  Future<void> clear() async {
    _entries.clear();
    await _save();
  }
}
