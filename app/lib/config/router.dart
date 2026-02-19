import 'package:go_router/go_router.dart';
import '../screens/onboarding/discover_screen.dart';
import '../screens/onboarding/pin_screen.dart';
import '../screens/onboarding/setup_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/photo_viewer/photo_viewer_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/settings/photo_picker_screen.dart';
import '../screens/settings/backup_log_screen.dart';

final router = GoRouter(
  initialLocation: '/discover',
  routes: [
    // Onboarding
    GoRoute(
      path: '/discover',
      builder: (_, __) => const DiscoverScreen(),
    ),
    GoRoute(
      path: '/pin',
      builder: (_, state) => PinScreen(
        serverHost: state.extra as String? ?? '',
      ),
    ),
    GoRoute(
      path: '/setup',
      builder: (_, __) => const SetupScreen(),
    ),
    // Main app (with bottom tabs)
    GoRoute(
      path: '/home',
      builder: (_, __) => const HomeScreen(),
    ),
    // Photo viewer
    GoRoute(
      path: '/photo/:id',
      builder: (_, state) => PhotoViewerScreen(
        photoId: state.pathParameters['id']!,
      ),
    ),
    // Settings
    GoRoute(
      path: '/settings',
      builder: (_, __) => const SettingsScreen(),
    ),
    // Photo picker (manual upload)
    GoRoute(
      path: '/pick-photos',
      builder: (_, __) => const PhotoPickerScreen(),
    ),
    // Backup log
    GoRoute(
      path: '/backup-log',
      builder: (_, __) => const BackupLogScreen(),
    ),
  ],
);
