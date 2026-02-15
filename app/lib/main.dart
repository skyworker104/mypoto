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
  @override
  void initState() {
    super.initState();
    // Try restoring session on app start
    Future.microtask(() {
      ref.read(authProvider.notifier).tryRestore();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authProvider);

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
