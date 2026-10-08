enum AudioVoice {
  standard('es-ES-Standard-H', 'Estándar · Standard-H'),
  premium('es-ES-Chirp3-HD-Autonoe', 'Premium · Autonoe');

  const AudioVoice(this.apiName, this.label);

  final String apiName;
  final String label;
}

class AudioParagraph {
  const AudioParagraph({
    required this.text,
    required this.cfiRange,
    this.runs = const [],
  });

  final String text;
  final String cfiRange;
  final List<AudioParagraph> runs;

  factory AudioParagraph.fromJson(Map<String, dynamic> json) => AudioParagraph(
    text: json['text'] as String,
    cfiRange: json['cfiRange'] as String,
    runs: (json['runs'] as List<dynamic>? ?? const [])
        .map((item) => AudioParagraph.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
  );
}

class AudioPage {
  const AudioPage({
    required this.startCfi,
    required this.endCfi,
    required this.href,
    required this.paragraphs,
    this.nextCfi,
  });

  final String startCfi;
  final String endCfi;
  final String? nextCfi;
  final String href;
  final List<AudioParagraph> paragraphs;

  String get text => paragraphs.map((paragraph) => paragraph.text).join('\n\n');

  factory AudioPage.fromJson(Map<String, dynamic> json) => AudioPage(
    startCfi: json['startCfi'] as String,
    endCfi: json['endCfi'] as String,
    nextCfi: json['nextCfi'] as String?,
    href: json['href'] as String? ?? '',
    paragraphs: (json['paragraphs'] as List<dynamic>)
        .map((item) => AudioParagraph.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
  );
}
