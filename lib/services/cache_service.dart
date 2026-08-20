import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class CacheService {
  CacheService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<Directory> get _cacheDirectory async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/rucio_epubs');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<String?> getCachedEpubPath(String bookId) async {
    final directory = await _cacheDirectory;
    final file = File('${directory.path}/$bookId.epub');
    return await file.exists() ? file.path : null;
  }

  Future<String> downloadAndCache(String bookId, String signedUrl) async {
    final directory = await _cacheDirectory;
    final target = File('${directory.path}/$bookId.epub');
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();
    try {
      await _dio.download(
        signedUrl,
        partial.path,
        options: Options(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
      return target.path;
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  Future<({HttpServer server, String url})> serveEpub(String epubPath) async {
    final file = File(epubPath);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      response.headers.set('Access-Control-Allow-Origin', '*');
      if (request.uri.path != '/book.epub') {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      response.headers.contentType = ContentType('application', 'epub+zip');
      response.contentLength = await file.length();
      await response.addStream(file.openRead());
      await response.close();
    });
    return (
      server: server,
      url: 'http://${server.address.address}:${server.port}/book.epub',
    );
  }
}
