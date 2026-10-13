class ClaudeContextSection {
  const ClaudeContextSection({
    required this.href,
    required this.text,
    this.isCurrent = false,
  });

  final String href;
  final String text;
  final bool isCurrent;

  factory ClaudeContextSection.fromJson(Map<String, dynamic> json) =>
      ClaudeContextSection(
        href: json['href'] as String,
        text: json['text'] as String,
        isCurrent: json['isCurrent'] as bool? ?? false,
      );
}

class ClaudeReadingContext {
  const ClaudeReadingContext({
    required this.cutoffCfi,
    required this.sections,
    required this.location,
    required this.boundaryLabel,
    this.title,
    this.author,
    this.percentage,
    this.chapterNumber,
    this.spineIndex,
  });

  final String cutoffCfi;
  final List<ClaudeContextSection> sections;
  final String location;
  final String boundaryLabel;
  final String? title;
  final String? author;
  final double? percentage;
  final int? chapterNumber;
  final int? spineIndex;

  String get positionSummary => [
    if (chapterNumber != null) 'Capítulo $chapterNumber',
    if (percentage != null) '${percentage!.toStringAsFixed(0)}% leído',
    if (chapterNumber == null && percentage == null) location,
    '${sections.length} secciones adjuntas',
  ].join(' · ');

  Map<String, dynamic> get metadata => {
    'cutoff_cfi': cutoffCfi,
    'location': location,
    'boundary_label': boundaryLabel,
    'title': title,
    'author': author,
    'percentage': percentage,
    'chapter_number': chapterNumber,
    'spine_index': spineIndex,
    'section_count': sections.length,
    'context_characters': sections.fold<int>(
      0,
      (sum, section) => sum + section.text.length,
    ),
  };
}
