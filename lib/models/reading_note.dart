class ReadingNote {
  final String id;
  final String userId;
  final String bookId;
  final String cfiRange;
  final String? selectedText;
  final String content;
  final String color;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? bookTitle;
  final String? bookAuthor;
  final bool bookIsArchived;

  const ReadingNote({
    required this.id,
    required this.userId,
    required this.bookId,
    required this.cfiRange,
    this.selectedText,
    required this.content,
    this.color = '#F2A65A',
    required this.createdAt,
    required this.updatedAt,
    this.bookTitle,
    this.bookAuthor,
    this.bookIsArchived = false,
  });

  factory ReadingNote.fromJson(Map<String, dynamic> json) {
    final book = json['books'];
    final bookData = book is Map<String, dynamic> ? book : null;
    return ReadingNote(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      bookId: json['book_id'] as String,
      cfiRange: json['cfi_range'] as String,
      selectedText: json['selected_text'] as String?,
      content: json['content'] as String,
      color: json['color'] as String? ?? '#F2A65A',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(
        (json['updated_at'] ?? json['created_at']) as String,
      ),
      bookTitle: bookData?['title'] as String?,
      bookAuthor: bookData?['author'] as String?,
      bookIsArchived: bookData?['epub_deleted_at'] != null,
    );
  }
}
