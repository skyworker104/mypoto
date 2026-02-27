import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/connectivity_provider.dart';
import '../home/photos_tab.dart';
import '../search/search_tab.dart';
import '../albums/albums_tab.dart';
import '../family/family_tab.dart';
import '../tv/tv_tab.dart';

/// Main screen with bottom navigation (5 tabs).
/// Disables server-dependent tabs when not connected.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  final _tabs = const [
    PhotosTab(),
    SearchTab(),
    AlbumsTab(),
    FamilyTab(),
    TvTab(),
  ];

  // Tabs that require server connection (indices 1-4)
  static const _serverRequiredTabs = {1, 2, 3, 4};

  @override
  Widget build(BuildContext context) {
    final connectivity = ref.watch(connectivityProvider);
    final isConnected = connectivity.isServerReachable;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          if (_serverRequiredTabs.contains(i) && !isConnected) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(connectivity.isWiFi
                    ? '동일 WiFi 존이 아닙니다'
                    : 'WiFi OFF 상태입니다'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }
          setState(() => _currentIndex = i);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: '사진',
          ),
          NavigationDestination(
            icon: Icon(Icons.search,
                color: isConnected ? null : Colors.grey[400]),
            selectedIcon: const Icon(Icons.search),
            label: '검색',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_album_outlined,
                color: isConnected ? null : Colors.grey[400]),
            selectedIcon: const Icon(Icons.photo_album),
            label: '앨범',
          ),
          NavigationDestination(
            icon: Icon(Icons.family_restroom_outlined,
                color: isConnected ? null : Colors.grey[400]),
            selectedIcon: const Icon(Icons.family_restroom),
            label: '가족',
          ),
          NavigationDestination(
            icon: Icon(Icons.tv_outlined,
                color: isConnected ? null : Colors.grey[400]),
            selectedIcon: const Icon(Icons.tv),
            label: 'TV',
          ),
        ],
      ),
    );
  }
}
