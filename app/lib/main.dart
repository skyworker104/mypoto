import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'config/theme.dart';
import 'config/router.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');
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
      await ref.read(authProvider.notifier).tryRestore();
      final authState = ref.read(authProvider);
      if (authState == AuthState.authenticated) {
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
