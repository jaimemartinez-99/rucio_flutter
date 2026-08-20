import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client_provider.dart';
import '../models/highlight.dart';

class HighlightsState {
  final List<Highlight> highlights;
  final bool isLoading;

  const HighlightsState({this.highlights = const [], this.isLoading = false});

  HighlightsState copyWith({List<Highlight>? highlights, bool? isLoading}) {
    return HighlightsState(
      highlights: highlights ?? this.highlights,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class HighlightsNotifier extends StateNotifier<HighlightsState> {
  final String? bookId;
  final Ref _ref;

  HighlightsNotifier(this._ref, {this.bookId}) : super(const HighlightsState());

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  Future<void> fetchHighlights() async {
    final userId = _userId;
    if (userId == null) return;

    state = state.copyWith(isLoading: true);
    final db = _ref.read(supabaseClientProvider);

    try {
      final query = bookId != null
          ? db
                .from('highlights')
                .select()
                .eq('user_id', userId)
                .eq('book_id', bookId!)
                .order('created_at', ascending: false)
          : db
                .from('highlights')
                .select()
                .eq('user_id', userId)
                .order('created_at', ascending: false);

      final response = await query;
      final highlights = (response as List)
          .map((json) => Highlight.fromJson(json as Map<String, dynamic>))
          .toList();

      state = state.copyWith(highlights: highlights, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> fetchHighlightsWithBooks() async {
    final userId = _userId;
    if (userId == null) return;

    state = state.copyWith(isLoading: true);
    final db = _ref.read(supabaseClientProvider);

    try {
      final response = await db
          .from('highlights')
          .select('*, books(id, title, author, epub_deleted_at)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final highlights = (response as List)
          .map((json) => Highlight.fromJson(json as Map<String, dynamic>))
          .toList();

      state = state.copyWith(highlights: highlights, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> addHighlight(
    String cfiRange,
    String text, {
    String color = '#ffff00',
    String? note,
  }) async {
    final userId = _userId;
    if (userId == null) return;

    final db = _ref.read(supabaseClientProvider);

    await db.from('highlights').insert({
      'user_id': userId,
      'book_id': bookId,
      'cfi_range': cfiRange,
      'text': text,
      'color': color,
      'note': note,
    });

    await fetchHighlights();
  }

  Future<void> deleteHighlight(String highlightId) async {
    final userId = _userId;
    if (userId == null) return;
    final db = _ref.read(supabaseClientProvider);

    await db
        .from('highlights')
        .delete()
        .eq('id', highlightId)
        .eq('user_id', userId);
    if (bookId == null) {
      await fetchHighlightsWithBooks();
    } else {
      await fetchHighlights();
    }
  }

  Future<void> updateHighlightColor(String highlightId, String color) async {
    final userId = _userId;
    if (userId == null) return;

    final db = _ref.read(supabaseClientProvider);
    await db
        .from('highlights')
        .update({'color': color})
        .eq('id', highlightId)
        .eq('user_id', userId);

    if (bookId == null) {
      await fetchHighlightsWithBooks();
    } else {
      await fetchHighlights();
    }
  }
}

final bookHighlightsProvider =
    StateNotifierProvider.family<HighlightsNotifier, HighlightsState, String>(
      (ref, bookId) => HighlightsNotifier(ref, bookId: bookId),
    );

final allHighlightsProvider =
    StateNotifierProvider<HighlightsNotifier, HighlightsState>((ref) {
      return HighlightsNotifier(ref);
    });
