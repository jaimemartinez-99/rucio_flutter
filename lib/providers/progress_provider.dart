import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client_provider.dart';
import '../models/reading_progress.dart';
import 'book_progresses_provider.dart';

class ProgressNotifier extends StateNotifier<ReadingProgress?> {
  final String bookId;
  final Ref _ref;
  Timer? _debounce;
  String? _pendingCfi;
  double _pendingPct = 0;

  ProgressNotifier(this._ref, this.bookId) : super(null);

  String? get lastCfi => state?.lastCfi;
  double get percentage => state?.percentage ?? 0;

  Future<void> fetchProgress() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final db = _ref.read(supabaseClientProvider);

    try {
      final response = await db
          .from('reading_progress')
          .select()
          .eq('user_id', userId)
          .eq('book_id', bookId)
          .maybeSingle();

      if (response != null) {
        state = ReadingProgress.fromJson(response);
      }
    } catch (_) {}
  }

  void saveProgress(String cfi, double pct) {
    if (cfi.isEmpty) return;
    _pendingCfi = cfi;
    _pendingPct = pct;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      _upsertProgress(_pendingCfi!, _pendingPct);
    });
  }

  Future<void> flushProgress() async {
    _debounce?.cancel();
    if (_pendingCfi != null) {
      await _upsertProgress(_pendingCfi!, _pendingPct);
    }
  }

  Future<void> _upsertProgress(String cfi, double pct) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final db = _ref.read(supabaseClientProvider);

    try {
      await db.from('reading_progress').upsert({
        'user_id': userId,
        'book_id': bookId,
        'last_cfi': cfi,
        'percentage': pct.clamp(0, 100),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,book_id');
      if (_pendingCfi == cfi && _pendingPct == pct) {
        _pendingCfi = null;
      }
      _ref.invalidate(bookProgressesProvider);
    } catch (_) {}
  }

  @override
  void dispose() {
    flushProgress();
    _debounce?.cancel();
    super.dispose();
  }
}

final progressProvider = StateNotifierProvider.family<
    ProgressNotifier, ReadingProgress?, String>(
  (ref, bookId) => ProgressNotifier(ref, bookId),
);
