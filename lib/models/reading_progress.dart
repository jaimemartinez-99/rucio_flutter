class ReadingProgress {
  final String userId;
  final String bookId;
  final String? lastCfi;
  final double percentage;
  final DateTime updatedAt;

  const ReadingProgress({
    required this.userId,
    required this.bookId,
    this.lastCfi,
    required this.percentage,
    required this.updatedAt,
  });

  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    return ReadingProgress(
      userId: json['user_id'] as String,
      bookId: json['book_id'] as String,
      lastCfi: json['last_cfi'] as String?,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'book_id': bookId,
      'last_cfi': lastCfi,
      'percentage': percentage,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
