import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sync_cache.dart';

class BackupSettings {
  final List<String> selectedAlbumIds;
  final Map<String, String> albumNames; // id -> name
  final bool autoBackupEnabled;

  const BackupSettings({
    this.selectedAlbumIds = const [],
    this.albumNames = const {},
    this.autoBackupEnabled = true,
  });

  bool get hasSelection => selectedAlbumIds.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'selectedAlbumIds': selectedAlbumIds,
        'albumNames': albumNames,
        'autoBackupEnabled': autoBackupEnabled,
      };

  factory BackupSettings.fromJson(Map<String, dynamic> json) {
    return BackupSettings(
      selectedAlbumIds: List<String>.from(json['selectedAlbumIds'] ?? []),
      albumNames: Map<String, String>.from(json['albumNames'] ?? {}),
      autoBackupEnabled: json['autoBackupEnabled'] as bool? ?? true,
    );
  }
}

class SettingsNotifier extends StateNotifier<BackupSettings> {
  static const _key = 'backup_settings';

  SettingsNotifier() : super(const BackupSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        state = BackupSettings.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
  }

  Future<void> setAutoBackup(bool enabled) async {
    state = BackupSettings(
      selectedAlbumIds: state.selectedAlbumIds,
      albumNames: state.albumNames,
      autoBackupEnabled: enabled,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.toJson()));
  }

  Future<void> save(List<String> albumIds, Map<String, String> names) async {
    state = BackupSettings(
      selectedAlbumIds: albumIds,
      albumNames: names,
      autoBackupEnabled: state.autoBackupEnabled,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.toJson()));
  }

  Future<void> clear() async {
    state = const BackupSettings();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, BackupSettings>((ref) {
  return SettingsNotifier();
});

/// Global SyncStateCache provider.
final syncCacheProvider = Provider<SyncStateCache>((ref) {
  final cache = SyncStateCache();
  cache.load(); // async but fire-and-forget; ready by the time backup starts
  return cache;
});
