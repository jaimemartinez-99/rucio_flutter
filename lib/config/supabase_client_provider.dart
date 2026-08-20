import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'supabase_config.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseClient(
    SupabaseConfig.url,
    SupabaseConfig.anonKey,
    postgrestOptions: const PostgrestClientOptions(schema: 'rucio'),
    accessToken: () async =>
        Supabase.instance.client.auth.currentSession?.accessToken,
  );
});
