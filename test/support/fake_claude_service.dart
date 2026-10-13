import 'dart:async';

import 'package:dio/dio.dart';
import 'package:rucio_flutter/models/claude_mode.dart';
import 'package:rucio_flutter/models/claude_reading_context.dart';
import 'package:rucio_flutter/services/claude_service.dart';

class FakeClaudeService extends ClaudeService {
  final modes = <ClaudeReadingMode>[];
  final questions = <String>[];
  int inputTokens = 12000;
  bool failPreparation = false;
  Completer<void>? firstPreparation;

  @override
  Future<ClaudePreparedQuestion> prepare(
    String question,
    String? selectedText, {
    required ClaudeReadingContext readingContext,
    ClaudeReadingMode mode = ClaudeReadingMode.economical,
    CancelToken? cancelToken,
  }) async {
    modes.add(mode);
    questions.add(question);
    if (modes.length == 1 && firstPreparation != null) {
      await firstPreparation!.future;
    }
    if (failPreparation) {
      throw const ClaudeServiceException('Token count unavailable');
    }
    return ClaudePreparedQuestion(
      question: question.trim(),
      selectedText: selectedText,
      readingContext: readingContext,
      mode: mode,
      inputTokens: inputTokens,
      request: {},
    );
  }
}
