import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client_provider.dart';
import '../models/claude_reading_context.dart';
import '../models/claude_usage.dart';
import '../models/claude_mode.dart';
import '../services/claude_service.dart';

class ClaudeMessage {
  final String question;
  final String answer;
  final String? selection;
  final DateTime createdAt;
  final ClaudeUsage? usage;
  final String? model;
  final String? cutoffCfi;
  final String? boundaryLabel;
  final String? warning;

  const ClaudeMessage({
    required this.question,
    required this.answer,
    this.selection,
    required this.createdAt,
    this.usage,
    this.model,
    this.cutoffCfi,
    this.boundaryLabel,
    this.warning,
  });

  factory ClaudeMessage.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] is Map
        ? json['metadata'] as Map
        : const {};
    return ClaudeMessage(
      question: json['question'] as String,
      answer: json['answer'] as String,
      selection: json['selection'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      usage: ClaudeUsage.fromJson(metadata['usage']),
      model: json['model'] as String?,
      cutoffCfi: metadata['cutoff_cfi'] as String?,
      boundaryLabel: metadata['boundary_label'] as String?,
      warning: metadata['warning'] as String?,
    );
  }
}

class ClaudeState {
  final List<ClaudeMessage> messages;
  final bool isLoading;
  final String? error;

  const ClaudeState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  ClaudeState copyWith({
    List<ClaudeMessage>? messages,
    bool? isLoading,
    String? error,
  }) {
    return ClaudeState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ClaudeNotifier extends StateNotifier<ClaudeState> {
  final String bookId;
  final ClaudeService _service;
  final Ref _ref;
  int _viewGeneration = 0;
  bool _isBusy = false;

  ClaudeNotifier(this._ref, this.bookId)
    : _service = _ref.read(claudeServiceProvider),
      super(const ClaudeState());

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  void clearVisibleMessages() {
    _viewGeneration++;
    state = ClaudeState(isLoading: _isBusy);
  }

  Future<void> fetchHistory() async {
    if (_isBusy) return;
    final userId = _userId;
    if (userId == null) return;

    final db = _ref.read(supabaseClientProvider);
    final generation = _viewGeneration;
    _isBusy = true;

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

      if (mounted && generation == _viewGeneration) {
        state = state.copyWith(messages: messages);
      }
    } catch (_) {
      if (mounted && generation == _viewGeneration) {
        state = state.copyWith(
          error: 'No se pudo cargar el historial de Claude.',
        );
      }
    } finally {
      _isBusy = false;
      if (mounted) state = state.copyWith(isLoading: false, error: state.error);
    }
  }

  Future<void> askQuestion(
    String? selectedText,
    String question, {
    required ClaudeReadingContext readingContext,
    ClaudeReadingMode mode = ClaudeReadingMode.economical,
    ClaudePreparedQuestion? preparedQuestion,
  }) async {
    if (question.trim().isEmpty || _isBusy) return;
    final generation = _viewGeneration;
    final userId = _userId;
    final db = _ref.read(supabaseClientProvider);
    _isBusy = true;

    state = state.copyWith(isLoading: true);

    try {
      final response = await _service.ask(
        question,
        selectedText,
        readingContext: readingContext,
        mode: mode,
        preparedQuestion: preparedQuestion,
      );

      final message = ClaudeMessage(
        question: question,
        answer: response.answer,
        selection: selectedText,
        createdAt: DateTime.now(),
        usage: response.usage,
        model: response.model,
        cutoffCfi: readingContext.cutoffCfi,
        boundaryLabel: readingContext.boundaryLabel,
        warning: response.warning,
      );

      if (mounted && generation == _viewGeneration) {
        state = state.copyWith(messages: [...state.messages, message]);
      }
      if (userId == null || userId != _userId) {
        if (mounted && generation == _viewGeneration) {
          state = state.copyWith(
            error:
                'La respuesta está visible, pero tu sesión ha caducado y no se pudo guardar.',
          );
        }
        return;
      }

      try {
        await db.from('claude_history').insert({
          'user_id': userId,
          'book_id': bookId,
          'question': question,
          'answer': response.answer,
          'selection': selectedText,
          'created_at': message.createdAt.toUtc().toIso8601String(),
          'model': response.model,
          'metadata': {
            ...readingContext.metadata,
            'usage': response.usage?.toJson(),
            'warning': response.warning,
            'reading_mode': mode.name,
            'estimated_input_tokens': preparedQuestion?.inputTokens,
            'estimated_max_usd': preparedQuestion?.estimatedMaxUsd,
          },
        });
      } catch (_) {
        if (mounted && generation == _viewGeneration) {
          state = state.copyWith(
            error:
                'La respuesta y su consumo están visibles, pero no se pudieron guardar en el historial.',
          );
        }
      }
    } finally {
      _isBusy = false;
      if (mounted) state = state.copyWith(isLoading: false, error: state.error);
    }
  }
}

final claudeProvider =
    StateNotifierProvider.family<ClaudeNotifier, ClaudeState, String>(
      (ref, bookId) => ClaudeNotifier(ref, bookId),
    );
