import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/claude_reading_context.dart';
import '../models/claude_retrieval.dart';

class ClaudeRetrievalService {
  static const defaultMaxCharacters = 20000;
  final _indexes = Expando<Future<_ReadingIndex>>();

  Future<ClaudeRetrieval> retrieve(
    ClaudeReadingContext context,
    String question,
    String? selectedText, {
    int maxCharacters = defaultMaxCharacters,
  }) async {
    final index = await (_indexes[context] ??= compute(
      _buildIndex,
      List<ClaudeContextSection>.unmodifiable(context.sections),
    ));
    return compute(
      _retrieve,
      _RetrievalRequest(index, question, selectedText, maxCharacters),
    );
  }
}

class _Chunk {
  _Chunk(this.sectionIndex, this.start, this.end, this.text, this.chapter) {
    final terms = _tokens(text);
    length = terms.length;
    for (final term in terms) {
      frequencies[term] = (frequencies[term] ?? 0) + 1;
    }
  }

  final int sectionIndex;
  final int start;
  final int end;
  final String text;
  final int? chapter;
  final Map<String, int> frequencies = {};
  late final int length;
}

class _ReadingIndex {
  _ReadingIndex(this.chunks, this.characters, this.sections) {
    var length = 0;
    final nameCounts = <String, int>{};
    for (final chunk in chunks) {
      length += chunk.length;
      for (final term in chunk.frequencies.keys) {
        documents[term] = (documents[term] ?? 0) + 1;
      }
      for (final match in RegExp(
        r'[a-záéíóúñ,;:»”)]\s+([A-ZÁÉÍÓÚÑ][a-záéíóúñ]+)',
      ).allMatches(chunk.text)) {
        for (final term in _tokens(match[1]!)) {
          nameCounts[term] = (nameCounts[term] ?? 0) + 1;
        }
      }
    }
    names.addAll(
      nameCounts.entries
          .where((entry) => entry.value >= 2)
          .map((entry) => entry.key),
    );
    averageLength = chunks.isEmpty ? 1 : math.max(1, length / chunks.length);
  }

  final List<_Chunk> chunks;
  final int characters;
  final int sections;
  final Map<String, int> documents = {};
  final Set<String> names = {};
  late final double averageLength;
}

class _RetrievalRequest {
  const _RetrievalRequest(
    this.index,
    this.question,
    this.selectedText,
    this.maxCharacters,
  );

  final _ReadingIndex index;
  final String question;
  final String? selectedText;
  final int maxCharacters;
}

String _normalize(String text) {
  const accents = 'áàäâãéèëêíìïîóòöôõúùüûç';
  const plain = 'aaaaaeeeeiiiiooooouuuuc';
  return text.toLowerCase().replaceAllMapped(
    RegExp('[$accents]'),
    (match) => plain[accents.indexOf(match[0]!)],
  );
}

final _words = RegExp(r'[a-z0-9ñ]+');
final _stopWords = {
  ...'a al algo algun alguna algunos ante asi aun aunque cada como con cual cuando de del desde donde el ella ellas ellos en entre era es esa ese eso esta estaba estar este esto fue ha habia hasta hay la las le les lo los mas me mi mis muy no nos o para pero por porque que quien se ser si sin sobre son su sus te tiene todo tu un una unos y ya'
      .split(' '),
  ...'about an and are as at be been before but by can did do does for from had has have he her him his how i if in into is it its me my of on or our she so some than that the their them then there these they this those to up us was we were what when where which who why will with would you your'
      .split(' '),
};

String _stem(String word) {
  if (RegExp(
    r'^(?:huy|hui|huir|escap|fug|march|desaparec|abandon|flee|fled|runaway|leave|leaves|left)',
  ).hasMatch(word)) {
    return 'leave_event';
  }
  if (RegExp(
    r'^(?:joven|juventud|niño|niña|infancia|muchach|young|child|youth)',
  ).hasMatch(word)) {
    return 'youth_stage';
  }
  if (word.length < 5) return word;
  final suffix = RegExp(
    r'(amientos|imientos|amiento|imiento|aciones|acion|amente|mente|ando|iendo|ados|adas|ado|ada|idos|idas|ido|ida|ing|ed|es|s)$',
  ).firstMatch(word);
  if (suffix != null && suffix.start >= 4) {
    return word.substring(0, suffix.start);
  }
  return word;
}

List<String> _tokens(String text) => _words
    .allMatches(_normalize(text))
    .map((match) => match[0]!)
    .where((word) => word.length > 1 && !_stopWords.contains(word))
    .map(_stem)
    .toList();

int? _chapterAt(String text, int offset) {
  int? chapter;
  final headings = RegExp(
    r'(?:^|\n)\s*(?:cap[ií]tulo|chapter|chapitre)\s+(\d+|[IVXLCDM]+)\b',
    caseSensitive: false,
  );
  for (final match in headings.allMatches(text)) {
    if (match.start > offset) break;
    final value = match[1]!.toUpperCase();
    chapter = int.tryParse(value);
    if (chapter != null) continue;
    const digits = {
      'I': 1,
      'V': 5,
      'X': 10,
      'L': 50,
      'C': 100,
      'D': 500,
      'M': 1000,
    };
    chapter = 0;
    for (var i = 0; i < value.length; i++) {
      final digit = digits[value[i]]!;
      chapter =
          chapter! +
          (i + 1 < value.length && digit < digits[value[i + 1]]!
              ? -digit
              : digit);
    }
  }
  return chapter;
}

_ReadingIndex _buildIndex(List<ClaudeContextSection> sections) {
  final chunks = <_Chunk>[];
  var characters = 0;
  for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
    final text = sections[sectionIndex].text;
    characters += text.length;
    var start = 0;
    while (start < text.length) {
      var end = math.min(start + 1400, text.length);
      if (end < text.length) {
        final paragraph = text.lastIndexOf('\n\n', end);
        if (paragraph > start + 700) {
          end = paragraph + 2;
        } else {
          final sentence = RegExp(
            r'[.!?…][»”"\x27]?\s',
          ).allMatches(text.substring(start, end)).lastOrNull;
          if (sentence != null && sentence.end > 700) {
            end = start + sentence.end;
          } else {
            final space = text.lastIndexOf(RegExp(r'\s'), end);
            if (space > start) {
              end = space + 1;
            } else {
              final unit = text.codeUnitAt(end - 1);
              if (unit >= 0xD800 && unit <= 0xDBFF) end--;
            }
          }
        }
      }
      final part = text.substring(start, end);
      if (part.trim().isNotEmpty) {
        chunks.add(
          _Chunk(sectionIndex, start, end, part, _chapterAt(text, start)),
        );
      }
      start = end;
    }
  }
  return _ReadingIndex(chunks, characters, sections.length);
}

Map<String, double> _queryTerms(String question, String? selection) {
  final terms = <String, double>{};
  for (final term in _tokens(question)) {
    terms[term] = term == 'youth_stage' ? 0.3 : 1;
  }
  for (final term in _tokens(selection ?? '').take(200)) {
    terms.putIfAbsent(term, () => 0.35);
  }
  final normalized = _normalize(question);
  final groups = [
    [
      r'\b(?:huy\w*|hui\w*|escap\w*|fug\w*|huida|flee\w*|ran away)\b',
      'huyo huye huir huida marcho marcharse marcha desaparecio abandono escapar fuga flee fled runaway',
    ],
    [
      r'\b(?:joven\w*|infancia|niñ\w*|young|child\w*|youth)\b',
      'joven juventud niño niña infancia young childhood youth',
    ],
    [
      r'\b(?:muere|murio|muerte|morir|dies|died|death)\b',
      'muere murio muerte morir fallecio fallecimiento dies died death',
    ],
    [
      r'\b(?:casar\w*|casad\w*|casam\w*|matrimonio|boda|marry|married|wedding)\b',
      'casar casarse casado matrimonio boda marry married wedding',
    ],
    [
      r'\b(?:abandona|abandon\w*|se marcha|leave|leaves|left)\b',
      'abandono marcha marcho desaparecio huye huyo leave leaves left',
    ],
  ];
  for (final group in groups) {
    if (RegExp(group[0]).hasMatch(normalized)) {
      for (final term in _tokens(group[1])) {
        terms.putIfAbsent(term, () => 0.65);
      }
    }
  }
  return terms;
}

ClaudeRetrieval _retrieve(_RetrievalRequest request) {
  final index = request.index;
  final chunks = index.chunks;
  final selected = <int>{};
  var characters = 0;
  bool add(int i) {
    if (i < 0 || i >= chunks.length || selected.contains(i)) return false;
    if (characters + chunks[i].text.length > request.maxCharacters) {
      return false;
    }
    selected.add(i);
    characters += chunks[i].text.length;
    return true;
  }

  if (index.characters <= request.maxCharacters) {
    for (var i = 0; i < chunks.length; i++) {
      add(i);
    }
  } else {
    final terms = _queryTerms(request.question, request.selectedText);
    final scores = <(int, double)>[];
    final entities = _tokens(
      request.question,
    ).where(index.names.contains).toSet();
    for (final entity in entities) {
      terms[entity] = 2;
    }
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      if (entities.isNotEmpty && !entities.any(chunk.frequencies.containsKey)) {
        continue;
      }
      var score = 0.0;
      for (final entry in terms.entries) {
        final frequency = chunk.frequencies[entry.key] ?? 0;
        if (frequency == 0) continue;
        final df = index.documents[entry.key]!;
        final idf = math.log(1 + (chunks.length - df + 0.5) / (df + 0.5));
        score +=
            entry.value *
            idf *
            frequency *
            2.2 /
            (frequency +
                1.2 * (0.25 + 0.75 * chunk.length / index.averageLength));
      }
      if (score > 0) scores.add((i, score));
    }
    scores.sort((a, b) {
      final comparison = b.$2.compareTo(a.$2);
      return comparison == 0 ? a.$1.compareTo(b.$1) : comparison;
    });
    add(chunks.length - 1);
    final selection = request.selectedText?.trim() ?? '';
    if (selection.isNotEmpty) {
      var foundSelection = false;
      for (var i = chunks.length - 1; i >= 0; i--) {
        if (chunks[i].text.contains(selection)) {
          foundSelection = true;
          add(i);
          for (final offset in [-1, -2, 1, 2]) {
            final neighbor = i + offset;
            if (neighbor >= 0 &&
                neighbor < chunks.length &&
                chunks[neighbor].sectionIndex == chunks[i].sectionIndex) {
              add(neighbor);
            }
          }
          break;
        }
      }
      if (!foundSelection) {
        for (
          var i = chunks.length - 2;
          i >= math.max(0, chunks.length - 3);
          i--
        ) {
          if (chunks[i].sectionIndex == chunks.last.sectionIndex) add(i);
        }
      }
    }
    final broad = RegExp(
      r'\b(?:resum\w*|summary|summarize|recap|so far)\b',
    ).hasMatch(_normalize(request.question));
    if (broad) {
      final count = math.max(1, request.maxCharacters ~/ 1400);
      for (var sample = 0; sample < count; sample++) {
        add((sample * (chunks.length - 1) / math.max(1, count - 1)).round());
      }
    } else {
      final anchors = <int>[];
      final anchorBudget = request.maxCharacters * 0.6;
      for (final (i, _) in scores) {
        if (selected.contains(i)) continue;
        if (!add(i)) continue;
        anchors.add(i);
        if (characters >= anchorBudget) break;
      }
      for (final i in anchors) {
        for (final offset in [-1, -2, 1, 2]) {
          final neighbor = i + offset;
          if (neighbor >= 0 &&
              neighbor < chunks.length &&
              chunks[neighbor].sectionIndex == chunks[i].sectionIndex) {
            add(neighbor);
          }
        }
      }
      for (final (i, _) in scores) {
        add(i);
      }
    }
  }

  final ordered = selected.toList()..sort();
  final passages = <ClaudeRetrievedPassage>[];
  for (final i in ordered) {
    final chunk = chunks[i];
    if (passages.isNotEmpty &&
        passages.last.sectionIndex == chunk.sectionIndex &&
        passages.last.end == chunk.start &&
        passages.last.chapterNumber == chunk.chapter) {
      final previous = passages.removeLast();
      passages.add(
        ClaudeRetrievedPassage(
          id: previous.id,
          sectionIndex: previous.sectionIndex,
          start: previous.start,
          end: chunk.end,
          text: previous.text + chunk.text,
          chapterNumber: previous.chapterNumber,
        ),
      );
    } else {
      passages.add(
        ClaudeRetrievedPassage(
          id: 'F${passages.length + 1}',
          sectionIndex: chunk.sectionIndex,
          start: chunk.start,
          end: chunk.end,
          text: chunk.text,
          chapterNumber: chunk.chapter,
        ),
      );
    }
  }
  return ClaudeRetrieval(
    passages: passages,
    sourceCharacters: index.characters,
    sourceSections: index.sections,
    isComplete: selected.length == chunks.length,
  );
}
