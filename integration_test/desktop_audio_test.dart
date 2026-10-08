import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rucio_flutter/models/book.dart';
import 'package:rucio_flutter/providers/highlights_provider.dart';
import 'package:rucio_flutter/providers/notes_provider.dart';
import 'package:rucio_flutter/providers/progress_provider.dart';
import 'package:rucio_flutter/screens/reader_screen.dart';
import 'package:rucio_flutter/services/audio_cache_service.dart';
import 'package:rucio_flutter/services/audio_playback.dart';
import 'package:rucio_flutter/services/google_tts_service.dart';
import 'package:rucio_flutter/services/reader_content_loader.dart';
import 'package:rucio_flutter/widgets/audiorucio_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _LocalBookLoader extends ReaderContentLoader {
  _LocalBookLoader(this.path, SupabaseClient client)
    : super(client: client, database: client);
  final String path;

  @override
  Future<ReaderContent> load(String bookId) async {
    final content = await loadCachedEpub(path);
    return ReaderContent(
      html: content.html,
      server: content.server,
      book: Book(
        id: bookId,
        userId: 'fixture',
        title: 'Libro de prueba',
        createdAt: DateTime(2026),
      ),
    );
  }
}

class _LocalProgress extends ProgressNotifier {
  _LocalProgress(Ref ref) : super(ref, 'fixture');
  @override
  Future<void> fetchProgress() async {}
  @override
  void saveProgress(String cfi, double pct) {}
  @override
  Future<void> flushProgress() async {}
}

class _LocalHighlights extends HighlightsNotifier {
  _LocalHighlights(super.ref) : super(bookId: 'fixture');
  @override
  Future<void> fetchHighlights() async {}
}

class _LocalNotes extends NotesNotifier {
  _LocalNotes(super.ref) : super(bookId: 'fixture');
  @override
  Future<void> fetchNotes({bool includeBooks = false}) async {}
}

List<int> fixtureEpub() {
  final archive = Archive();
  final files = {
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    'OPS/package.opf':
        '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">fixture</dc:identifier><dc:title>Libro de prueba</dc:title><dc:language>es</dc:language></metadata><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest><spine toc="ncx"><itemref idref="chapter"/></spine></package>',
    'OPS/toc.ncx':
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head/><docTitle><text>Libro</text></docTitle><navMap><navPoint id="one" playOrder="1"><navLabel><text>Capítulo de prueba</text></navLabel><content src="chapter.xhtml"/></navPoint></navMap></ncx>',
    'OPS/chapter.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Prueba</title></head><body><h1>Capítulo de prueba</h1><p>Una frase para escuchar en Audiorucio.</p><p>El texto conserva su posición dentro del libro.</p></body></html>',
  };
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}

Uint8List silentWave() {
  const samples = 24000 * 3;
  final bytes = Uint8List(44 + samples * 2);
  final data = ByteData.sublistView(bytes);
  void text(int offset, String value) =>
      bytes.setRange(offset, offset + value.length, value.codeUnits);
  text(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 24000, Endian.little);
  data.setUint32(28, 48000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  return bytes;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'The Windows EPUB reader opens Audiorucio with real CFI text and returns to the book',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'audiorucio_reader_',
      );
      final file = await File(
        '${directory.path}/fixture.epub',
      ).writeAsBytes(fixtureEpub());
      final client = SupabaseClient('https://fixture.example', 'fixture');
      final tts = GoogleTtsService()..apiKey = '';
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              readerContentLoaderProvider.overrideWithValue(
                _LocalBookLoader(file.path, client),
              ),
              googleTtsServiceProvider.overrideWithValue(tts),
              audioCacheServiceProvider.overrideWithValue(
                AudioCacheService(
                  directory: Directory('${directory.path}/audio'),
                ),
              ),
              progressProvider.overrideWith((ref, _) => _LocalProgress(ref)),
              bookHighlightsProvider.overrideWith(
                (ref, _) => _LocalHighlights(ref),
              ),
              bookNotesProvider.overrideWith((ref, _) => _LocalNotes(ref)),
            ],
            child: MaterialApp(
              theme: ThemeData.dark(useMaterial3: true),
              home: const ReaderScreen(bookId: 'fixture'),
            ),
          ),
        );
        for (
          var attempt = 0;
          attempt < 100 &&
              find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
          attempt++
        ) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.tap(find.byTooltip('Herramientas de lectura'));
        await tester.pumpAndSettle();
        expect(find.text('Iniciar Audiorucio'), findsOneWidget);
        await tester.tap(find.text('Iniciar Audiorucio'));
        for (
          var attempt = 0;
          attempt < 100 &&
              find
                  .text('Una frase para escuchar en Audiorucio.')
                  .evaluate()
                  .isEmpty;
          attempt++
        ) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(find.byType(AudioRucioPlayer), findsOneWidget);
        expect(
          find.text('Una frase para escuchar en Audiorucio.'),
          findsOneWidget,
        );
        expect(find.text('Libro de prueba'), findsWidgets);
        expect(find.text('Conectar'), findsOneWidget);
        await tester.tap(find.byTooltip('Consumo mensual'));
        await tester.pumpAndSettle();
        expect(
          find.text('Coste estimado tras el tramo gratuito'),
          findsOneWidget,
        );
        expect(find.text('0 caracteres generados'), findsNWidgets(2));
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Volver al libro'));
        await tester.pumpAndSettle();
        expect(find.byType(AudioRucioPlayer), findsNothing);
        expect(find.byTooltip('Herramientas de lectura'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await client.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );

  testWidgets('Windows plays, pauses, seeks and releases a local audio file', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Verificando audio de Audiorucio…')),
        ),
      ),
    );
    final directory = await Directory.systemTemp.createTemp(
      'audiorucio_native_',
    );
    final file = await File(
      '${directory.path}/silence.wav',
    ).writeAsBytes(silentWave());
    final audio = DesktopAudioPlayback();
    final errors = <String>[];
    final subscription = audio.errors.listen(errors.add);
    try {
      await audio.setVolume(0);
      await audio.load(file.path);
      expect((await audio.getDuration())!.inMilliseconds, closeTo(3000, 100));
      await audio.resume();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await audio.pause();
      await audio.seek(const Duration(seconds: 1));
      await audio.resume();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await audio.stop();
      await file.delete();
      expect(await file.exists(), isFalse);
      expect(errors, isEmpty);
    } finally {
      await subscription.cancel();
      await audio.dispose();
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isWindows);
}
