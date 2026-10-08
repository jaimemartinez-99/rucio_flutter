class EpubFootnote {
  const EpubFootnote({
    required this.requestId,
    required this.label,
    this.isLoading = false,
    this.text,
    this.error,
  });

  final String requestId;
  final String label;
  final bool isLoading;
  final String? text;
  final String? error;

  factory EpubFootnote.fromJson(Map<String, dynamic> json) => EpubFootnote(
    requestId: json['requestId'] as String,
    label: json['label'] as String? ?? '',
    isLoading: json['loading'] == true,
    text: json['text'] as String?,
    error: json['error'] as String?,
  );
}
