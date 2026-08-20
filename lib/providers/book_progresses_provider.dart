import 'auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/supabase_client_provider.dart';

final bookProgressesProvider =
    FutureProvider<Map<String, double>>((ref) async {
  final userId = ref.watch(authProvider.select((state) => state.user?.id));
  if (userId == null) return {};

  final db = ref.read(supabaseClientProvider);

  try {
    final response = await db
        .from('reading_progress')
        .select()
        .eq('user_id', userId);

    final map = <String, double>{};
    for (final row in response as List) {
      final r = row as Map<String, dynamic>;
      map[r['book_id'] as String] = (r['percentage'] as num).toDouble();
    }
    return map;
  } catch (_) {
    return {};
  }
});
