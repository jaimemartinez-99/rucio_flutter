import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rucio_flutter/models/claude_reading_context.dart';
import 'package:rucio_flutter/services/claude_service.dart';

void main() {
  const path = String.fromEnvironment('CLAUDE_BOOK_FIXTURE');
  test(
    'Haiku answers an already-read event at chapter XVII instead of claiming the book just started',
    () async {
      final data =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      final context = ClaudeReadingContext(
        cutoffCfi: data['cutoffCfi'] as String,
        sections: (data['sections'] as List)
            .map(
              (section) => ClaudeContextSection.fromJson(
                section as Map<String, dynamic>,
              ),
            )
            .toList(),
        title: data['title'] as String?,
        author: data['author'] as String?,
        location: data['location'] as String,
        boundaryLabel: data['boundaryLabel'] as String,
        percentage: (data['percentage'] as num?)?.toDouble() ?? 52,
        chapterNumber: data['chapterNumber'] as int? ?? 17,
        spineIndex: data['spineIndex'] as int?,
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        final response = await ClaudeService().ask(
          'Por que huye Heathcliff de joven?',
          null,
          readingContext: context,
        );
        debugPrint(response.answer);
        debugPrint(
          'Book regression: ${response.usage?.totalInputTokens} input tokens; ${response.usage?.estimatedUsd} USD estimated.',
        );
        final answer = response.answer.toLowerCase();
        expect(answer, isNot(contains('inicio del libro')));
        expect(answer, isNot(contains('ningún capítulo')));
        expect(answer, isNot(contains('todavía no has leído')));
        expect(
          answer,
          isNot(
            contains('episodio concreto de su desaparición aún no aparece'),
          ),
        );
        expect(answer, contains('catherine'));
        expect(answer, contains('casar'));
        expect(
          answer,
          anyOf(
            contains('oyó'),
            contains('escuch'),
            contains('oír'),
            contains('oido'),
            contains('oído'),
          ),
        );
        expect(
          answer,
          anyOf(contains('degrad'), contains('humill'), contains('rechaz')),
        );
        expect(response.usage, isNotNull);
      }
    },
    skip: !const bool.fromEnvironment('RUN_CLAUDE_BOOK_TEST') || path.isEmpty,
  );
}
