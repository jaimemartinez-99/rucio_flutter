import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client_provider.dart';
import '../models/book.dart';
import 'cache_service.dart';

class ReaderContent {
  const ReaderContent({required this.html, this.server, this.book});

  final String html;
  final HttpServer? server;
  final Book? book;

  Future<void> dispose() async {
    await server?.close(force: true);
  }
}

class ReaderContentLoader {
  ReaderContentLoader({required this.client, required this.database});

  final SupabaseClient client;
  final SupabaseClient database;
  final _cache = CacheService();

  Future<ReaderContent> load(String bookId) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Tu sesión ha caducado. Inicia sesión de nuevo.');
    }
    final book = await database
        .from('books')
        .select()
        .eq('id', bookId)
        .eq('user_id', userId)
        .single();
    final filePath = book['file_path'] as String?;
    if (filePath == null) throw StateError('Este EPUB ya no está disponible.');

    var epubPath = await _cache.getCachedEpubPath(bookId);
    if (epubPath == null) {
      final url = await client.storage
          .from('libros')
          .createSignedUrl(filePath, 3600);
      epubPath = await _cache.downloadAndCache(bookId, url);
    }
    final content = await loadCachedEpub(epubPath);
    return ReaderContent(
      html: content.html,
      server: content.server,
      book: Book.fromJson(book),
    );
  }

  Future<ReaderContent> loadCachedEpub(String epubPath) async {
    if (await File(epubPath).length() == 0) {
      throw StateError('El EPUB descargado está vacío.');
    }
    final sources = await Future.wait([
      rootBundle.loadString('assets/reader.html'),
      rootBundle.loadString('assets/epubjs/jszip.min.js'),
      rootBundle.loadString('assets/epubjs/epub.min.js'),
      rootBundle.loadString('assets/epubjs/footnotes.js'),
      rootBundle.loadString('assets/epubjs/audiorucio.js'),
    ]);
    var html = sources[0]
        .replaceFirst('{{{JSZIP_SOURCE}}}', sources[1])
        .replaceFirst('{{{EPUBJS_SOURCE}}}', sources[2])
        .replaceFirst('{{{FOOTNOTES_SOURCE}}}', sources[3])
        .replaceFirst('{{{AUDIORUCIO_SOURCE}}}', sources[4]);
    final local = await _cache.serveEpub(epubPath);
    html = html
        .replaceFirst('{{{EPUB_URL_JSON}}}', jsonEncode(local.url))
        .replaceFirst('{{{EPUB_DATA_JSON}}}', 'null');
    return ReaderContent(html: html, server: local.server);
  }
}

final readerContentLoaderProvider = Provider<ReaderContentLoader>((ref) {
  return ReaderContentLoader(
    client: Supabase.instance.client,
    database: ref.read(supabaseClientProvider),
  );
});
