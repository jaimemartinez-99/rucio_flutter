import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../screens/highlights_screen.dart';
import '../screens/library_screen.dart';
import '../screens/login_screen.dart';
import '../screens/notes_screen.dart';
import '../screens/reader_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = authState.user != null;
      final isLoggingIn = state.uri.path == '/login';

      if (authState.isLoading) return null;

      if (!isLoggedIn && !isLoggingIn) return '/login';
      if (isLoggedIn && isLoggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const LibraryScreen(),
      ),
      GoRoute(
        path: '/reader/:bookId',
        builder: (context, state) {
          final bookId = state.pathParameters['bookId']!;
          final cfi = state.uri.queryParameters['cfi'];
          return ReaderScreen(bookId: bookId, initialCfi: cfi);
        },
      ),
      GoRoute(
        path: '/highlights',
        builder: (context, state) => const HighlightsScreen(),
      ),
      GoRoute(
        path: '/notes',
        builder: (context, state) => const NotesScreen(),
      ),
    ],
  );
});
