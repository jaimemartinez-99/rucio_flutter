class ClaudeRetrievedPassage {
  const ClaudeRetrievedPassage({
    required this.id,
    required this.sectionIndex,
    required this.start,
    required this.end,
    required this.text,
    this.chapterNumber,
  });

  final String id;
  final int sectionIndex;
  final int start;
  final int end;
  final String text;
  final int? chapterNumber;

  String get label => chapterNumber == null
      ? 'Sección ${sectionIndex + 1}'
      : 'Capítulo $chapterNumber';

  Map<String, dynamic> get metadata => {
    'id': id,
    'section_index': sectionIndex,
    'start': start,
    'end': end,
    'chapter_number': chapterNumber,
  };
}

class ClaudeRetrieval {
  ClaudeRetrieval({
    required List<ClaudeRetrievedPassage> passages,
    required this.sourceCharacters,
    required this.sourceSections,
    required this.isComplete,
  }) : passages = List.unmodifiable(passages);

  final List<ClaudeRetrievedPassage> passages;
  final int sourceCharacters;
  final int sourceSections;
  final bool isComplete;

  int get retrievedCharacters =>
      passages.fold(0, (sum, passage) => sum + passage.text.length);

  Map<String, dynamic> get metadata => {
    'version': 'local-bm25-v1',
    'source_characters': sourceCharacters,
    'source_sections': sourceSections,
    'retrieved_characters': retrievedCharacters,
    'complete_prefix': isComplete,
    'passage_count': passages.length,
    'passages': passages.map((passage) => passage.metadata).toList(),
  };
}
