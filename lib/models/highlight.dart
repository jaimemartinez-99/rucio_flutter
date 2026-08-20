class HighlightColorOption {
  final String label;
  final String description;
  final String value;

  const HighlightColorOption({
    required this.label,
    required this.description,
    required this.value,
  });

  static const beautiful = HighlightColorOption(
    label: 'Frase bella',
    description: 'Una frase que quieres recordar',
    value: '#F87171',
  );
  static const reflection = HighlightColorOption(
    label: 'Reflexion',
    description: 'Una idea para pensar',
    value: '#60A5FA',
  );
  static const turningPoint = HighlightColorOption(
    label: 'Punto de inflexion',
    description: 'Un cambio importante del personaje',
    value: '#FACC15',
  );

  static const values = [beautiful, reflection, turningPoint];

  static HighlightColorOption fromValue(String value) {
    return values.firstWhere(
      (option) => option.value.toLowerCase() == value.toLowerCase(),
      orElse: () => turningPoint,
    );
  }
}

class Highlight {
  final String id;
  final String userId;
  final String bookId;
  final String cfiRange;
  final String text;
  final String color;
  final String? note;
  final DateTime createdAt;
  final String? bookTitle;
  final String? bookAuthor;
  final bool bookIsArchived;

  const Highlight({
    required this.id,
    required this.userId,
    required this.bookId,
    required this.cfiRange,
    required this.text,
    this.color = '#ffff00',
    this.note,
    required this.createdAt,
    this.bookTitle,
    this.bookAuthor,
    this.bookIsArchived = false,
  });

  factory Highlight.fromJson(Map<String, dynamic> json) {
    final book = json['books'];
    final bookData = book is Map<String, dynamic> ? book : null;
    return Highlight(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      bookId: json['book_id'] as String,
      cfiRange: json['cfi_range'] as String,
      text: json['text'] as String,
      color: json['color'] as String? ?? '#ffff00',
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      bookTitle: bookData?['title'] as String?,
      bookAuthor: bookData?['author'] as String?,
      bookIsArchived: bookData?['epub_deleted_at'] != null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'book_id': bookId,
      'cfi_range': cfiRange,
      'text': text,
      'color': color,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
