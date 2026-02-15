import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/map_provider.dart';

/// Map screen showing photo locations as a list of location clusters.
/// Uses a simple list-based layout (no external map SDK dependency).
class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clustersAsync = ref.watch(mapClustersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('사진 지도')),
      body: clustersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('위치 로딩 실패: $e')),
        data: (clusters) {
          if (clusters.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('위치 정보가 있는 사진이 없습니다',
                      style: TextStyle(color: Colors.grey)),
                  Text('GPS가 포함된 사진을 업로드하세요',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: clusters.length,
            itemBuilder: (context, index) {
              final cluster = clusters[index];
              return _LocationClusterCard(cluster: cluster);
            },
          );
        },
      ),
    );
  }
}

class _LocationClusterCard extends StatelessWidget {
  final LocationCluster cluster;

  const _LocationClusterCard({required this.cluster});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: SizedBox(
          width: 56,
          height: 56,
          child: cluster.coverThumbUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: cluster.coverThumbUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: Colors.grey[200]),
                    errorWidget: (_, __, ___) =>
                        Container(
                          color: Colors.grey[300],
                          child: const Icon(Icons.photo, color: Colors.grey),
                        ),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.location_on, color: Colors.grey),
                ),
        ),
        title: Text(
          cluster.locationName ?? '(${cluster.lat.toStringAsFixed(3)}, ${cluster.lon.toStringAsFixed(3)})',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('${cluster.count}장'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // Navigate to location detail (photo grid)
        },
      ),
    );
  }
}
