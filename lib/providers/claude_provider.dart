import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client_provider.dart';
import '../services/claude_service.dart';

class ClaudeMessage {
  final String question;
  final String answer;
  final String? selection;
  final DateTime createdAt;

  const ClaudeMessage({
    required this.question,
    required this.answer,
    this.selection,
    required this.createdAt,
  });

  factory ClaudeMessage.fromJson(Map<String, dynamic> json) {
    return ClaudeMessage(
      question: json['question'] as String,
      answer: json['answer'] as String,
      selection: json['selection'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ClaudeState {
  final List<ClaudeMessage> messages;
  final bool isLoading;

  const ClaudeState({this.messages = const [], this.isLoading = false});

  ClaudeState copyWith({List<ClaudeMessage>? messages, bool? isLoading}) {
    return ClaudeState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ClaudeNotifier extends StateNotifier<ClaudeState> {
  final String bookId;
  final ClaudeService _service;
  final Ref _ref;

  ClaudeNotifier(this._ref, this.bookId)
    : _service = ClaudeService(),
      super(const ClaudeState());

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  void clearVisibleMessages() {
    state = const ClaudeState();
  }

  Future<void> fetchHistory() async {
    final userId = _userId;
    if (userId == null) return;

    final db = _ref.read(supabaseClientProvider);

    state = state.copyWith(isLoading: true);
    try {
      final response = await db
          .from('claude_history')
          .select()
          .eq('user_id', userId)
          .eq('book_id', bookId)
          .order('created_at', ascending: true);

      final messages = (response as List)
          .map((json) => ClaudeMessage.fromJson(json as Map<String, dynamic>))
          .toList();

      state = state.copyWith(messages: messages, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> askQuestion(
    String? selectedText,
    String question, {
    String? readingContext,
  }) async {
    if (question.trim().isEmpty) return;

    state = state.copyWith(isLoading: true);

    try {
      final answer = await _service.ask(
        question,
        selectedText,
        readingContext: readingContext,
      );

      final messages = [
        ...state.messages,
        ClaudeMessage(
          question: question,
          answer: answer,
          selection: selectedText,
          createdAt: DateTime.now(),
        ),
      ];

      state = state.copyWith(messages: messages, isLoading: false);
      final userId = _userId;
      if (userId == null) return;

      try {
        final db = _ref.read(supabaseClientProvider);
        await db.from('claude_history').insert({
          'user_id': userId,
          'book_id': bookId,
          'question': question,
          'answer': answer,
          'selection': selectedText,
        });
      } catch (_) {}
    } catch (_) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }
}

final claudeProvider =
    StateNotifierProvider.family<ClaudeNotifier, ClaudeState, String>(
      (ref, bookId) => ClaudeNotifier(ref, bookId),
    );
