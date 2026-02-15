import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// Screen for manually selecting photos to upload.
/// Returns List<AssetEntity> via Navigator.pop.
class PhotoPickerScreen extends StatefulWidget {
  const PhotoPickerScreen({super.key});

  @override
  State<PhotoPickerScreen> createState() => _PhotoPickerScreenState();
}

class _PhotoPickerScreenState extends State<PhotoPickerScreen> {
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _currentAlbum;
  List<AssetEntity> _assets = [];
  final Set<String> _selectedIds = {};
  final Map<String, AssetEntity> _selectedAssets = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
    );
    if (albums.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _albums = albums;
      _currentAlbum = albums.first;
    });
    _loadAssets(albums.first);
  }

  Future<void> _loadAssets(AssetPathEntity album) async {
    setState(() => _loading = true);
    final count = await album.assetCountAsync;
    final assets = await album.getAssetListRange(start: 0, end: count);
    setState(() {
      _assets = assets;
      _loading = false;
    });
  }

  void _toggleSelection(AssetEntity asset) {
    setState(() {
      if (_selectedIds.contains(asset.id)) {
        _selectedIds.remove(asset.id);
        _selectedAssets.remove(asset.id);
      } else {
        _selectedIds.add(asset.id);
        _selectedAssets[asset.id] = asset;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('사진 선택 (${_selectedIds.length}장)'),
        actions: [
          TextButton(
            onPressed: _selectedIds.isEmpty
                ? null
                : () {
                    Navigator.pop(context, _selectedAssets.values.toList());
                  },
            child: const Text('완료'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Album selector dropdown
          if (_albums.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: DropdownButton<AssetPathEntity>(
                value: _currentAlbum,
                isExpanded: true,
                items: _albums.map((album) {
                  return DropdownMenuItem(
                    value: album,
                    child: Text(album.name),
                  );
                }).toList(),
                onChanged: (album) {
                  if (album != null) {
                    setState(() => _currentAlbum = album);
                    _loadAssets(album);
                  }
                },
              ),
            ),
          // Photo grid
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _assets.isEmpty
                    ? const Center(child: Text('사진이 없습니다'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(2),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 2,
                          mainAxisSpacing: 2,
                        ),
                        itemCount: _assets.length,
                        itemBuilder: (context, index) {
                          final asset = _assets[index];
                          final isSelected = _selectedIds.contains(asset.id);
                          return GestureDetector(
                            onTap: () => _toggleSelection(asset),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _AssetThumbnail(asset: asset),
                                if (isSelected)
                                  Container(
                                    color: Colors.blue.withValues(alpha: 0.3),
                                    alignment: Alignment.topRight,
                                    padding: const EdgeInsets.all(4),
                                    child: const Icon(
                                      Icons.check_circle,
                                      color: Colors.blue,
                                      size: 24,
                                    ),
                                  )
                                else
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 2),
                                      ),
                                    ),
                                  ),
                                if (asset.type == AssetType.video)
                                  const Positioned(
                                    bottom: 4,
                                    left: 4,
                                    child: Icon(Icons.videocam,
                                        color: Colors.white, size: 18),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _AssetThumbnail extends StatelessWidget {
  final AssetEntity asset;

  const _AssetThumbnail({required this.asset});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
          );
        }
        return Container(color: Colors.grey[300]);
      },
    );
  }
}
