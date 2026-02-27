import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'config/theme.dart';
import 'config/router.dart';
import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');
  await NotificationService.init();
  await NotificationService.requestPermission();
  runApp(const ProviderScope(child: PhotoNestApp()));
}

class PhotoNestApp extends ConsumerStatefulWidget {
  const PhotoNestApp({super.key});

  @override
  ConsumerState<PhotoNestApp> createState() => _PhotoNestAppState();
}

class _PhotoNestAppState extends ConsumerState<PhotoNestApp> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      // Restore session with 5s safety timeout to prevent infinite splash
      try {
        await ref
            .read(authProvider.notifier)
            .tryRestore()
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Timeout or error → treat as unauthenticated
      }

      final authState = ref.read(authProvider);

      // Pre-initialize connectivity check before home screen loads
      if (authState == AuthState.authenticated) {
        ref.read(connectivityProvider);
        router.go('/home');
      }
      if (mounted) setState(() => _initialized = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authProvider);

    // Show splash while restoring session
    if (!_initialized) {
      return MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('PhotoNest', style: TextStyle(fontSize: 24)),
              ],
            ),
          ),
        ),
      );
    }

    return MaterialApp.router(
      title: 'PhotoNest',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
