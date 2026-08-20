import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client_provider.dart';
import '../models/reading_note.dart';

class NotesState {
  final List<ReadingNote> notes;
  final bool isLoading;

  const NotesState({this.notes = const [], this.isLoading = false});

  NotesState copyWith({List<ReadingNote>? notes, bool? isLoading}) {
    return NotesState(
      notes: notes ?? this.notes,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class NotesNotifier extends StateNotifier<NotesState> {
  NotesNotifier(this._ref, {this.bookId}) : super(const NotesState());

  final Ref _ref;
  final String? bookId;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  Future<void> fetchNotes({bool includeBooks = false}) async {
    final userId = _userId;
    if (userId == null) return;

    state = state.copyWith(isLoading: true);
    final db = _ref.read(supabaseClientProvider);

    try {
      var query = db
          .from('notes')
          .select(includeBooks ? '*, books(id, title, author, epub_deleted_at)' : '*')
          .eq('user_id', userId);
      if (bookId != null) query = query.eq('book_id', bookId!);
      final response = await query.order('updated_at', ascending: false);
      state = state.copyWith(
        notes: (response as List)
            .map((item) => ReadingNote.fromJson(item as Map<String, dynamic>))
            .toList(),
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<ReadingNote> addNote({
    required String cfiRange,
    required String content,
    String? selectedText,
    String color = '#F2A65A',
  }) async {
    final userId = _userId;
    if (userId == null || bookId == null) {
      throw StateError('No active reading session.');
    }

    final db = _ref.read(supabaseClientProvider);
    final response = await db
        .from('notes')
        .insert({
          'user_id': userId,
          'book_id': bookId,
          'cfi_range': cfiRange,
          'selected_text': selectedText,
          'content': content,
          'color': color,
        })
        .select()
        .single();
    final note = ReadingNote.fromJson(response);
    state = state.copyWith(notes: [note, ...state.notes]);
    return note;
  }

  Future<void> updateNote(
    String noteId, {
    required String content,
    required String color,
  }) async {
    final userId = _userId;
    if (userId == null) return;
    final db = _ref.read(supabaseClientProvider);
    final response = await db
        .from('notes')
        .update({
          'content': content,
          'color': color,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', noteId)
        .eq('user_id', userId)
        .select()
        .single();
    final updated = ReadingNote.fromJson(response);
    state = state.copyWith(
      notes: [
        for (final note in state.notes) if (note.id == noteId) updated else note,
      ],
    );
  }

  Future<void> deleteNote(String noteId) async {
    final userId = _userId;
    if (userId == null) return;
    final db = _ref.read(supabaseClientProvider);
    await db.from('notes').delete().eq('id', noteId).eq('user_id', userId);
    state = state.copyWith(
      notes: state.notes.where((note) => note.id != noteId).toList(),
    );
  }
}

final bookNotesProvider =
    StateNotifierProvider.family<NotesNotifier, NotesState, String>(
      (ref, bookId) => NotesNotifier(ref, bookId: bookId),
    );

final allNotesProvider = StateNotifierProvider<NotesNotifier, NotesState>(
  (ref) => NotesNotifier(ref),
);
