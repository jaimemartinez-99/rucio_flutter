import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  runApp(
    const ProviderScope(
      child: RucioApp(),
    ),
  );
}

class RucioApp extends ConsumerWidget {
  const RucioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Rucio',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0f0e17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFf2a65a),
          onPrimary: Color(0xFF0f0e17),
          surface: Color(0xFF1a1827),
          onSurface: Color(0xFFe8e4f0),
          error: Color(0xFFf87171),
        ),
        cardColor: const Color(0xFF1a1827),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1a1827),
          foregroundColor: Color(0xFFe8e4f0),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFf2a65a),
          foregroundColor: Color(0xFF0f0e17),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFFf2a65a),
          linearTrackColor: Color(0xFF252336),
        ),
      ),
      routerConfig: router,
    );
  }
}
