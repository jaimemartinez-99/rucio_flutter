import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rucio_flutter/models/claude_reading_context.dart';
import 'package:rucio_flutter/services/claude_retrieval_service.dart';

ClaudeReadingContext contextWith(List<String> sections) => ClaudeReadingContext(
  cutoffCfi: 'epubcfi(/6/44!/4/2/1:0)',
  sections: [
    for (var i = 0; i < sections.length; i++)
      ClaudeContextSection(
        href: 'file-$i.xhtml',
        text: sections[i],
        isCurrent: i == sections.length - 1,
      ),
  ],
  location: '52% leído',
  boundaryLabel: 'Hasta el inicio de la página actual',
  chapterNumber: 17,
  percentage: 52,
);

String filler(int n) => List.generate(
  n,
  (i) =>
      'El viajero recorre el campo y observa los árboles junto al río. La lluvia cae sobre el camino y la casa permanece cerrada. La jornada termina en silencio.',
).join('\n\n');

void main() {
  test(
    'Keeps a small prefix complete with exact source offsets and safe labels',
    () async {
      final context = contextWith([
        'CAPÍTULO IX\n\nCatherine habla con Nelly.',
        'CAPÍTULO XVII\n\nLa lluvia cesó.',
      ]);
      final result = await ClaudeRetrievalService().retrieve(
        context,
        '¿Qué sucede?',
        null,
      );
      expect(result.isComplete, true);
      expect(result.passages.map((p) => p.chapterNumber), [9, 17]);
      expect(result.passages.map((p) => p.id), ['F1', 'F2']);
      for (final passage in result.passages) {
        expect(
          passage.text,
          context.sections[passage.sectionIndex].text.substring(
            passage.start,
            passage.end,
          ),
        );
      }
      expect(jsonEncode(result.metadata), isNot(contains('Catherine habla')));
      expect(jsonEncode(result.metadata), isNot(contains('file-')));
    },
  );

  test(
    'Retrieves an old cause and nearby dialogue instead of all prior chapters',
    () async {
      final context = contextWith([
        filler(80),
        'CAPÍTULO IX\n\n${filler(35)}\n\nCatherine dijo a Nelly que casarse con Heathcliff la degradaría socialmente. Heathcliff la escuchó desde la cocina y se marchó.\n\nÉl no oyó que ella confesaba su amor por él. Esa noche desapareció sin despedirse.\n\n${filler(35)}',
        filler(80),
      ]);
      final result = await ClaudeRetrievalService().retrieve(
        context,
        '¿Por qué huye Heathcliff de joven?',
        null,
      );
      final text = result.passages.map((p) => p.text).join('\n');
      expect(text, contains('la degradaría'));
      expect(text, contains('no oyó'));
      expect(result.isComplete, false);
      expect(result.retrievedCharacters, lessThanOrEqualTo(20000));
      expect(
        result.retrievedCharacters,
        lessThan(result.sourceCharacters ~/ 2),
      );
      expect(result.passages.any((p) => p.chapterNumber == 9), true);
    },
  );

  test(
    'A different question retrieves different evidence from the same prefix',
    () async {
      final context = contextWith([
        '${filler(40)}\n\nLa capitana Aurora escondió la brújula en una caja azul.\n\n${filler(40)}',
        '${filler(40)}\n\nEl cocinero Jacinto guardó la receta en un armario rojo.\n\n${filler(40)}',
        filler(40),
      ]);
      final service = ClaudeRetrievalService();
      final first = await service.retrieve(
        context,
        '¿Dónde escondió Aurora la brújula?',
        null,
      );
      final second = await service.retrieve(
        context,
        '¿Dónde guardó Jacinto la receta?',
        null,
      );
      expect(first.passages.map((p) => p.text).join(), contains('caja azul'));
      expect(
        second.passages.map((p) => p.text).join(),
        contains('armario rojo'),
      );
      expect(
        first.passages.map((p) => p.text).join(),
        isNot(contains('armario rojo')),
      );
      expect(
        second.passages.map((p) => p.text).join(),
        isNot(contains('caja azul')),
      );
    },
  );

  test(
    'Rewinding cannot reuse evidence from a later boundary or another book',
    () async {
      final service = ClaudeRetrievalService();
      final later = contextWith([filler(40), 'El asesino era Zafiro.']);
      final earlier = contextWith([filler(40), 'Zafiro miraba la ventana.']);
      await service.retrieve(later, '¿Quién era Zafiro?', null);
      final result = await service.retrieve(
        earlier,
        '¿Quién era Zafiro?',
        null,
      );
      final text = result.passages.map((p) => p.text).join();
      expect(text, contains('miraba la ventana'));
      expect(text, isNot(contains('asesino')));
      expect(
        result.sourceCharacters,
        earlier.sections.fold<int>(0, (sum, s) => sum + s.text.length),
      );
    },
  );

  test(
    'Keeps selected passage context and orders disjoint excerpts chronologically',
    () async {
      const selected = 'Ella recordó el acuerdo que habían firmado.';
      final context = contextWith([
        '${filler(35)}\n\n$selected\n\nSu amiga había prometido guardar silencio.\n\n${filler(35)}',
        '${filler(35)}\n\nEl acuerdo se rompió durante la discusión.\n\n${filler(35)}',
        filler(30),
      ]);
      final result = await ClaudeRetrievalService().retrieve(
        context,
        'Explica este acuerdo',
        selected,
      );
      final text = result.passages.map((p) => p.text).join();
      expect(text, contains(selected));
      expect(text, contains('Su amiga había prometido'));
      expect(text, contains('se rompió'));
      final offsets = result.passages
          .map((p) => p.sectionIndex * 1000000 + p.start)
          .toList();
      expect(offsets, orderedEquals([...offsets]..sort()));
    },
  );

  test(
    'Handles accents, summaries, empty prefixes and Unicode without exceeding budget',
    () async {
      final context = contextWith([
        'CAPÍTULO I\n\n${filler(40)}\n\nLa brújula indicó el norte. 😀\n\n${filler(40)}',
        'CAPÍTULO II\n\n${filler(80)}',
        'CAPÍTULO III\n\n${filler(80)}',
      ]);
      final service = ClaudeRetrievalService();
      final search = await service.retrieve(
        context,
        '¿Qué indica la brujula?',
        null,
      );
      expect(
        search.passages.map((p) => p.text).join(),
        contains('brújula indicó'),
      );
      final summary = await service.retrieve(
        context,
        'Resume lo leído hasta ahora',
        null,
      );
      expect(summary.passages.map((p) => p.sectionIndex).toSet(), {0, 1, 2});
      expect(summary.retrievedCharacters, lessThanOrEqualTo(20000));
      for (final passage in summary.passages) {
        expect(utf8.decode(utf8.encode(passage.text)), passage.text);
      }
      expect(
        (await service.retrieve(contextWith([]), 'Pregunta', null)).passages,
        isEmpty,
      );
    },
  );

  const fixturePath = String.fromEnvironment('CLAUDE_BOOK_FIXTURE');
  test(
    'Splitting long unbroken text preserves UTF-16 boundaries and the local budget',
    () async {
      final text = '${'a' * 1399}😀${'b' * 40000}';
      final result = await ClaudeRetrievalService().retrieve(
        contextWith([text]),
        'Texto',
        null,
      );
      expect(result.passages, isNotEmpty);
      expect(result.retrievedCharacters, lessThanOrEqualTo(20000));
      for (final passage in result.passages) {
        expect(utf8.decode(utf8.encode(passage.text)), passage.text);
        expect(passage.text, text.substring(passage.start, passage.end));
      }
    },
  );

  test(
    'Local retrieval finds the Heathcliff scene in the actual chapter XVII prefix',
    () async {
      final data =
          jsonDecode(await File(fixturePath).readAsString())
              as Map<String, dynamic>;
      final context = ClaudeReadingContext(
        cutoffCfi: data['cutoffCfi'] as String,
        sections: (data['sections'] as List)
            .map(
              (s) => ClaudeContextSection.fromJson(s as Map<String, dynamic>),
            )
            .toList(),
        location: data['location'] as String,
        boundaryLabel: data['boundaryLabel'] as String,
        chapterNumber: 17,
        percentage: 52,
      );
      final stopwatch = Stopwatch()..start();
      final service = ClaudeRetrievalService();
      final result = await service.retrieve(
        context,
        'Por que huye Heathcliff de joven?',
        null,
      );
      stopwatch.stop();
      final text = result.passages.map((p) => p.text).join().toLowerCase();
      expect(text.contains('degrad'), true);
      expect(text.contains('catherine'), true);
      expect(text.contains('casar'), true);
      expect(text.contains('había oído hasta que catherine dijo'), true);
      for (final question in [
        'por que huye heathcliff de joven?',
        '¿Por qué se marcha Heathcliff?',
      ]) {
        final alternative = await service.retrieve(context, question, null);
        expect(
          alternative.passages.any(
            (p) => p.text.toLowerCase().contains(
              'había oído hasta que catherine dijo',
            ),
          ),
          true,
        );
      }
      expect(result.isComplete, false);
      expect(result.retrievedCharacters, lessThanOrEqualTo(20000));
      debugPrint(
        'Local book retrieval: ${result.passages.length} passages, ${result.retrievedCharacters}/${result.sourceCharacters} characters, ${stopwatch.elapsedMilliseconds} ms.',
      );
    },
    skip: fixturePath.isEmpty,
  );
}
