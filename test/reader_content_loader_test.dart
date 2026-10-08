import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rucio_flutter/services/reader_content_loader.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late SupabaseClient client;
  late ReaderContentLoader loader;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rucio_reader_');
    client = SupabaseClient('https://rucio.example', 'test-key');
    loader = ReaderContentLoader(client: client, database: client);
  });

  tearDown(() async {
    await client.dispose();
    await directory.delete(recursive: true);
  });

  test('Large cached books stay outside the WebView HTML size limit', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final bytes = Uint8List(3 * 1024 * 1024);
      for (var index = 0; index < bytes.length; index++) {
        bytes[index] = index % 251;
      }
      final file = File('${directory.path}/large.epub');
      await file.writeAsBytes(bytes);
      final content = await loader.loadCachedEpub(file.path);
      final http = HttpClient();
      try {
        expect(utf8.encode(content.html).length, lessThan(2 * 1024 * 1024));
        expect(content.html, isNot(contains('{{{')));
        final url = RegExp(
          r'var epubUrl = "([^"]+)";',
        ).firstMatch(content.html)!.group(1)!;
        final uri = Uri.parse(url);
        expect(uri.host, InternetAddress.loopbackIPv4.address);

        for (var attempt = 0; attempt < 2; attempt++) {
          final request = await http.getUrl(uri);
          final response = await request.close();
          expect(response.statusCode, HttpStatus.ok);
          expect(response.headers.value('Access-Control-Allow-Origin'), '*');
          expect(response.contentLength, bytes.length);
          final received = await response.fold<List<int>>(
            <int>[],
            (buffer, chunk) => buffer..addAll(chunk),
          );
          expect(received, orderedEquals(bytes));
        }

        await content.dispose();
        await expectLater(() async {
          final request = await http.getUrl(uri);
          await request.close();
        }, throwsA(anyOf(isA<SocketException>(), isA<HttpException>())));
      } finally {
        http.close(force: true);
        await content.dispose();
      }
    }, _RealHttpOverrides());
  });

  test('Empty cached books fail before initializing the reader', () async {
    final file = File('${directory.path}/empty.epub');
    await file.writeAsBytes([]);
    await expectLater(
      loader.loadCachedEpub(file.path),
      throwsA(isA<StateError>()),
    );
  });
}
