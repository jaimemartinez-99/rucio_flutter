class Book {
  final String id;
  final String userId;
  final String title;
  final String? author;
  final String? coverUrl;
  final String? filePath;
  final int? fileSize;
  final DateTime? epubDeletedAt;
  final DateTime createdAt;

  const Book({
    required this.id,
    required this.userId,
    required this.title,
    this.author,
    this.coverUrl,
    this.filePath,
    this.fileSize,
    this.epubDeletedAt,
    required this.createdAt,
  });

  Book copyWith({
    String? id,
    String? userId,
    String? title,
    String? author,
    String? coverUrl,
    String? filePath,
    int? fileSize,
    DateTime? epubDeletedAt,
    DateTime? createdAt,
  }) {
    return Book(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      author: author ?? this.author,
      coverUrl: coverUrl ?? this.coverUrl,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      epubDeletedAt: epubDeletedAt ?? this.epubDeletedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      author: json['author'] as String?,
      coverUrl: json['cover_url'] as String?,
      filePath: json['file_path'] as String?,
      fileSize: json['file_size'] as int?,
      epubDeletedAt: json['epub_deleted_at'] == null
          ? null
          : DateTime.parse(json['epub_deleted_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'author': author,
      'cover_url': coverUrl,
      'file_path': filePath,
      'file_size': fileSize,
      'epub_deleted_at': epubDeletedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
