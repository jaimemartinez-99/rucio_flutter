import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart' show SupabaseClient;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:xml/xml.dart';

import '../config/supabase_client_provider.dart';
import '../models/book.dart';

class BooksState {
  final List<Book> books;
  final bool isLoading;
  final String searchQuery;

  const BooksState({
    this.books = const [],
    this.isLoading = false,
    this.searchQuery = '',
  });

  BooksState copyWith({
    List<Book>? books,
    bool? isLoading,
    String? searchQuery,
  }) {
    return BooksState(
      books: books ?? this.books,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class BooksNotifier extends StateNotifier<BooksState> {
  final Ref _ref;

  BooksNotifier(this._ref) : super(const BooksState());

  SupabaseClient get _db {
    return _ref.read(supabaseClientProvider);
  }

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  List<Book> get filteredBooks {
    if (state.searchQuery.isEmpty) return state.books;
    final q = state.searchQuery.toLowerCase();
    return state.books.where((b) {
      return b.title.toLowerCase().contains(q) ||
          (b.author?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> fetchBooks() async {
    final userId = _userId;
    if (userId == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final response = await _db
          .from('books')
          .select()
          .eq('user_id', userId)
          .isFilter('epub_deleted_at', null)
          .order('created_at', ascending: false);

      final books = (response as List)
          .map((json) => Book.fromJson(json as Map<String, dynamic>))
          .toList();

      state = state.copyWith(books: books, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  void searchBooks(String query) {
    state = state.copyWith(searchQuery: query);
  }

  Future<void> uploadEpub() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Could not read the selected EPUB file.');
    }

    final metadata = _parseEpubMetadata(bytes);
    final title = metadata['title'] ?? file.name.replaceAll('.epub', '');
    final author = metadata['author'];
    final coverBase64 = metadata['cover'];

    final userId = _userId;
    if (userId == null) return;

    final storagePath = '$userId/${file.name}';
    await Supabase.instance.client.storage
        .from('libros')
        .uploadBinary(storagePath, bytes);

    final dbRow = {
      'user_id': userId,
      'title': title,
      'author': author,
      'cover_url': coverBase64,
      'file_path': storagePath,
      'file_size': file.size,
    };

    await _db.from('books').insert(dbRow);

    await fetchBooks();
  }

  Future<void> removeEpub(Book book) async {
    final userId = _userId;
    if (userId == null || book.filePath == null) return;

    await Supabase.instance.client.storage.from('libros').remove([
      book.filePath!,
    ]);
    await _db
        .from('books')
        .update({
          'file_path': null,
          'file_size': null,
          'epub_deleted_at': DateTime.now().toIso8601String(),
        })
        .eq('id', book.id)
        .eq('user_id', userId);
    await fetchBooks();
  }

  Future<void> deleteBookPermanently(Book book) async {
    final userId = _userId;
    if (userId == null) return;

    await _db.from('books').delete().eq('id', book.id).eq('user_id', userId);
    if (book.filePath != null) {
      await Supabase.instance.client.storage.from('libros').remove([
        book.filePath!,
      ]);
    }
    await fetchBooks();
  }

  Map<String, String?> _parseEpubMetadata(Uint8List bytes) {
    final result = <String, String?>{'title': null, 'author': null, 'cover': null};

    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      String? rootfilePath;
      for (final file in archive) {
        if (file.isFile && file.name == 'META-INF/container.xml') {
          final content = utf8.decode(file.content as List<int>);
          final doc = XmlDocument.parse(content);
          final rootfile = doc.findAllElements('rootfile').firstOrNull;
          rootfilePath = rootfile?.getAttribute('full-path');
          break;
        }
      }

      if (rootfilePath == null) return result;

      for (final file in archive) {
        if (file.isFile && file.name == rootfilePath) {
          final content = utf8.decode(file.content as List<int>);
          final doc = XmlDocument.parse(content);
          final metadata = doc.findAllElements('metadata').firstOrNull;
          if (metadata != null) {
            result['title'] = _findElementText(metadata, 'dc:title') ??
                _findElementText(metadata, 'title');
            result['author'] = _findElementText(metadata, 'dc:creator') ??
                _findElementText(metadata, 'creator');
          }

          final opfDir = rootfilePath.contains('/')
              ? rootfilePath.substring(0, rootfilePath.lastIndexOf('/') + 1)
              : '';

          String? coverId;
          for (final meta in doc.findAllElements('meta')) {
            if (meta.getAttribute('name') == 'cover') {
              coverId = meta.getAttribute('content');
              break;
            }
          }

          String? coverHref;
          if (coverId != null) {
            for (final item in doc.findAllElements('item')) {
              if (item.getAttribute('id') == coverId) {
                coverHref = item.getAttribute('href');
                break;
              }
            }
          }

          if (coverHref == null) {
            for (final item in doc.findAllElements('item')) {
              final mediaType = item.getAttribute('media-type') ?? '';
              if (mediaType.startsWith('image/') &&
                  (item.getAttribute('id')?.toLowerCase().contains('cover') ?? false)) {
                coverHref = item.getAttribute('href');
                break;
              }
            }
          }

          if (coverHref != null) {
            final coverPath = opfDir + coverHref;
            for (final file in archive) {
              if (file.isFile &&
                  file.name.replaceAll('\\', '/') == coverPath.replaceAll('\\', '/')) {
                final coverBytes = file.content as List<int>;
                final ext = coverPath.split('.').last.toLowerCase();
                final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
                result['cover'] =
                    'data:$mime;base64,${base64Encode(coverBytes)}';
                break;
              }
            }
          }
          break;
        }
      }
    } catch (_) {}

    return result;
  }

  String? _findElementText(XmlElement parent, String tagName) {
    for (final node in parent.children) {
      if (node is XmlElement) {
        final local = node.localName;
        final prefixed = node.name.qualified;
        if (local == tagName ||
            prefixed == tagName ||
            local == tagName.split(':').last) {
          return node.innerText.trim();
        }
        final found = _findElementText(node, tagName);
        if (found != null) return found;
      }
    }
    return null;
  }
}

final booksProvider =
    StateNotifierProvider<BooksNotifier, BooksState>((ref) {
  return BooksNotifier(ref);
});
