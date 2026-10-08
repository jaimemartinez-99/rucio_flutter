import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rucio_flutter/models/book.dart';
import 'package:rucio_flutter/models/audio_page.dart';
import 'package:rucio_flutter/providers/audiorucio_provider.dart';
import 'package:dio/dio.dart';
import 'package:rucio_flutter/providers/highlights_provider.dart';
import 'package:rucio_flutter/providers/notes_provider.dart';
import 'package:rucio_flutter/providers/progress_provider.dart';
import 'package:rucio_flutter/screens/reader_screen.dart';
import 'package:rucio_flutter/services/audio_cache_service.dart';
import 'package:rucio_flutter/services/audio_playback.dart';
import 'package:rucio_flutter/services/google_tts_service.dart';
import 'package:rucio_flutter/services/reader_content_loader.dart';
import 'package:rucio_flutter/services/reader_webview.dart';
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

List<int> fixtureEpub({String? body}) {
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
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Prueba</title></head><body>${body ?? '<h1>Capítulo de prueba</h1><p>Una frase para escuchar en Audiorucio.</p><p>El texto conserva su posición dentro del libro.</p>'}</body></html>',
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

class _SilentTts extends GoogleTtsService {
  _SilentTts() {
    apiKey = 'fixture';
  }
  int calls = 0;
  @override
  Future<Uint8List> synthesize(
    String text,
    AudioVoice voice, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    return silentWave();
  }
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

  testWidgets(
    'Audio pages follow real Windows pagination and preloading leaves the reader in place',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'audiorucio_pages_',
      );
      final body = List.generate(
        100,
        (i) =>
            '<p>Párrafo $i. ${'Una historia larga con árboles, caminos y palabras para escuchar. ' * 12}</p>',
      ).join();
      final file = await File(
        '${directory.path}/fixture.epub',
      ).writeAsBytes(fixtureEpub(body: body));
      final client = SupabaseClient('https://fixture.example', 'fixture');
      final content = await ReaderContentLoader(
        client: client,
        database: client,
      ).loadCachedEpub(file.path);
      final web = ReaderWebView.create();
      final pending = <String, Completer<String>>{};
      var relocations = 0;
      final messages = web.messages.listen((event) {
        if (event.channel == 'Relocated') relocations++;
        final waiting = pending[event.channel];
        if (waiting != null && !waiting.isCompleted) {
          waiting.complete(event.message);
        }
      });
      Future<Map<String, dynamic>> evaluate(String script) async {
        final response = Completer<String>();
        pending['Probe'] = response;
        await web.runJavaScript(
          '(async function() { try { $script } catch(error) { postToFlutter("Probe", JSON.stringify({failure:String(error)})); } })()',
        );
        return jsonDecode(
              await tester.runAsync(
                    () => response.future.timeout(const Duration(seconds: 20)),
                  ) ??
                  '{}',
            )
            as Map<String, dynamic>;
      }

      Future<Map<String, dynamic>> audioPage(String cfi) async {
        final response = Completer<String>();
        pending['AudioPage'] = response;
        await web.runJavaScript('requestAudioPage(1, ${jsonEncode(cfi)})');
        final result =
            jsonDecode(
                  await tester.runAsync(
                        () => response.future.timeout(
                          const Duration(seconds: 20),
                        ),
                      ) ??
                      '{}',
                )
                as Map<String, dynamic>;
        expect(result['error'], isNull);
        return result['page'] as Map<String, dynamic>;
      }

      try {
        await web.initialize();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 1000,
                  height: 600,
                  child: web.buildView(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final ready = Completer<String>();
        pending['ReaderReady'] = ready;
        await web.loadHtml(content.html);
        await tester.runAsync(
          () => ready.future.timeout(const Duration(seconds: 20)),
        );
        var previousLength = 0;
        for (final settings in [
          (18, 30, 'one'),
          (30, 100, 'one'),
          (18, 30, 'two'),
        ]) {
          final visible = await evaluate('''
          closeAudioReader();
          setStyles('body,p { font-size: ${settings.$1}px !important; line-height: 1.7 !important; } body { padding: 10px ${settings.$2}px 20px !important; }');
          await setPageLayout('${settings.$3}');
          await displayAfterLayout(0);
          await new Promise(resolve => setTimeout(resolve, 150));
          await rendition.reportLocation();
          postToFlutter('Probe', JSON.stringify(rendition.currentLocation()));
        ''');
          expect(visible['failure'], isNull);
          final first = await audioPage(visible['start']['cfi'] as String);
          expect(first['startCfi'], visible['start']['cfi']);
          expect(first['endCfi'], visible['end']['cfi']);
          final length = (first['paragraphs'] as List).fold<int>(
            0,
            (sum, p) => sum + (p['text'] as String).length,
          );
          expect(length, greaterThan(100));
          if (settings.$1 == 30) expect(length, lessThan(previousLength));
          if (settings.$3 == 'two') expect(length, greaterThan(previousLength));
          previousLength = length;
          final before = relocations;
          final second = await audioPage(first['nextCfi'] as String);
          expect(relocations, before);
          final source = await evaluate('''
            var section = book.spine.get(${jsonEncode(first['startCfi'])});
            await section.load(book.load.bind(book));
            var doc = section.document;
            var start = new ePub.CFI(${jsonEncode(first['startCfi'])}).toRange(doc);
            var end = new ePub.CFI(${jsonEncode(first['endCfi'])}).toRange(doc);
            var nextStart = new ePub.CFI(${jsonEncode(second['startCfi'])}).toRange(doc);
            var range = doc.createRange();
            range.setStart(start.startContainer, start.startOffset);
            range.setEnd(end.startContainer, end.startOffset);
            var gap = doc.createRange();
            gap.setStart(end.startContainer, end.startOffset);
            gap.setEnd(nextStart.startContainer, nextStart.startOffset);
            postToFlutter('Probe', JSON.stringify({text:range.toString(), gap:gap.toString(), order:new ePub.CFI().compare(${jsonEncode(first['endCfi'])}, ${jsonEncode(second['startCfi'])})}));
          ''');
          final spoken = (first['paragraphs'] as List)
              .map((p) => p['text'])
              .join();
          expect(
            spoken.replaceAll(RegExp(r'\s'), ''),
            (source['text'] as String).replaceAll(RegExp(r'\s'), ''),
          );
          expect((source['gap'] as String).trim(), isEmpty);
          expect(source['order'] as num, lessThanOrEqualTo(0));
          final after = await evaluate(
            "postToFlutter('Probe', JSON.stringify(rendition.currentLocation()));",
          );
          expect(after['start']['cfi'], first['startCfi']);
          final next = await evaluate(
            "await rendition.next(); await new Promise(resolve => setTimeout(resolve, 100)); await rendition.reportLocation(); postToFlutter('Probe', JSON.stringify(rendition.currentLocation()));",
          );
          expect(second['startCfi'], next['start']['cfi']);
          expect(second['endCfi'], next['end']['cfi']);
        }
      } finally {
        await messages.cancel();
        await tester.pumpWidget(const SizedBox());
        await web.dispose();
        await content.dispose();
        await client.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'The native audio controller continues through pages without another play action',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'audiorucio_continuous_',
      );
      final tts = _SilentTts();
      final visited = <String>[];
      final controller = AudioRucioController(
        session: AudioSession(
          userId: 'fixture',
          bookId: 'continuous',
          initialCfi: '0',
          loadPage: (cfi) async {
            final index = int.parse(cfi ?? '0');
            return AudioPage(
              startCfi: '$index',
              endCfi: '$index-end',
              nextCfi: index < 2 ? '${index + 1}' : null,
              href: 'chapter',
              paragraphs: [
                AudioParagraph(
                  text: 'Página $index.',
                  cfiRange: '$index-range',
                ),
              ],
            );
          },
          onPageChanged: (page) async {
            visited.add(page.startCfi);
          },
        ),
        tts: tts,
        cache: AudioCacheService(directory: directory),
        player: DesktopAudioPlayback(),
      );
      try {
        await controller.initialize();
        expect(controller.isPlaying, isFalse);
        expect(tts.calls, 0);
        await controller.setVolume(0);
        final ended = Completer<void>();
        controller.addListener(() {
          if ((controller.finished || controller.error != null) &&
              !ended.isCompleted) {
            ended.complete();
          }
        });
        await controller.togglePlayback();
        await tester.runAsync(
          () => ended.future.timeout(const Duration(seconds: 20)),
        );
        expect(controller.error, isNull);
        expect(controller.finished, isTrue);
        expect(controller.isPlaying, isFalse);
        expect(visited, ['0', '1', '2']);
        expect(tts.calls, 3);
      } finally {
        await controller.close();
        controller.dispose();
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

  testWidgets(
    'Windows delivers completion events across repeated player lifetimes',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'audiorucio_events_',
      );
      final file = await File(
        '${directory.path}/silence.wav',
      ).writeAsBytes(silentWave());
      try {
        for (var iteration = 0; iteration < 3; iteration++) {
          final audio = DesktopAudioPlayback();
          final errors = <String>[];
          final durations = <Duration>[];
          final errorSubscription = audio.errors.listen(errors.add);
          final durationSubscription = audio.durations.listen(durations.add);
          try {
            await audio.setVolume(0);
            await audio.load(file.path);
            final completion = audio.completions.first.timeout(
              const Duration(seconds: 10),
            );
            await audio.seek(const Duration(milliseconds: 2700));
            await audio.resume();
            await completion;
            expect(durations, isNotEmpty);
            expect(durations.last.inMilliseconds, closeTo(3000, 100));
            expect(errors, isEmpty);
          } finally {
            await durationSubscription.cancel();
            await errorSubscription.cancel();
            await audio.dispose();
          }
        }
        await file.delete();
        expect(await file.exists(), isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}
