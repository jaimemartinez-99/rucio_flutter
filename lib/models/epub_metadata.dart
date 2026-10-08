enum EpubPageCountSource { metadata, pageList }

class EpubMetadata {
  const EpubMetadata({
    this.title,
    this.authors = const [],
    this.contributors = const [],
    this.publisher,
    this.languages = const [],
    this.publicationDate,
    this.identifiers = const [],
    this.subjects = const [],
    this.description,
    this.pageCount,
    this.pageCountSource,
    this.series,
    this.fileSize,
  });

  final String? title;
  final List<String> authors;
  final List<String> contributors;
  final String? publisher;
  final List<String> languages;
  final String? publicationDate;
  final List<String> identifiers;
  final List<String> subjects;
  final String? description;
  final int? pageCount;
  final EpubPageCountSource? pageCountSource;
  final String? series;
  final int? fileSize;
}
