import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent cache mapping file hashes to server photo IDs
/// and local asset IDs to file hashes.
class SyncStateCache {
  static const _hashToServerKey = 'sync_hash_to_server';
  static const _assetToHashKey = 'sync_asset_to_hash';

  Map<String, String> _hashToServerId = {};
  Map<String, String> _assetIdToHash = {};
  bool _loaded = false;

  /// Load cache from SharedPreferences.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final h2s = prefs.getString(_hashToServerKey);
    final a2h = prefs.getString(_assetToHashKey);
    if (h2s != null) {
      _hashToServerId = Map<String, String>.from(jsonDecode(h2s));
    }
    if (a2h != null) {
      _assetIdToHash = Map<String, String>.from(jsonDecode(a2h));
    }
    _loaded = true;
  }

  /// Save cache to SharedPreferences.
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hashToServerKey, jsonEncode(_hashToServerId));
    await prefs.setString(_assetToHashKey, jsonEncode(_assetIdToHash));
  }

  /// Check if a file hash exists on server.
  bool isSynced(String fileHash) => _hashToServerId.containsKey(fileHash);

  /// Get server photo ID for a file hash.
  String? getServerId(String fileHash) => _hashToServerId[fileHash];

  /// Get file hash for a local asset ID.
  String? getHashForAsset(String assetId) => _assetIdToHash[assetId];

  /// Check if a local asset is synced to server.
  bool isAssetSynced(String assetId) {
    final hash = _assetIdToHash[assetId];
    if (hash == null) return false;
    return _hashToServerId.containsKey(hash);
  }

  /// Add a hash → serverId mapping.
  void addMapping(String hash, String serverId) {
    _hashToServerId[hash] = serverId;
  }

  /// Add a local assetId → hash mapping.
  void addLocalHash(String assetId, String hash) {
    _assetIdToHash[assetId] = hash;
  }

  /// Batch update: mark existing hashes as synced (server already has them).
  void markExistingHashes(Set<String> existingHashes) {
    for (final hash in existingHashes) {
      if (!_hashToServerId.containsKey(hash)) {
        _hashToServerId[hash] = '_existing';
      }
    }
  }

  /// Batch add mappings from upload results.
  void addBatchMappings(Map<String, String> hashToId) {
    _hashToServerId.addAll(hashToId);
  }

  /// Number of synced photos.
  int get syncedCount => _hashToServerId.length;

  /// Number of locally hashed photos.
  int get localHashedCount => _assetIdToHash.length;

  /// Count synced assets for given asset IDs.
  int countSyncedAssets(List<String> assetIds) {
    int count = 0;
    for (final id in assetIds) {
      if (isAssetSynced(id)) count++;
    }
    return count;
  }
}
