import 'package:flutter/material.dart';

/// Albums tab - placeholder for Sprint 5.
class AlbumsTab extends StatelessWidget {
  const AlbumsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('앨범'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              // TODO: create album
            },
          ),
        ],
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_album_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('앨범을 만들어 사진을 정리하세요',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
