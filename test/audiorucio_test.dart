import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rucio_flutter/models/audio_page.dart';
import 'package:rucio_flutter/models/book.dart';
import 'package:rucio_flutter/providers/audiorucio_provider.dart';
import 'package:rucio_flutter/services/audio_cache_service.dart';
import 'package:rucio_flutter/services/audio_playback.dart';
import 'package:rucio_flutter/services/google_tts_service.dart';
import 'package:rucio_flutter/widgets/audiorucio_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAudioPlayback implements AudioPlayback {
  final positionEvents = StreamController<Duration>.broadcast(sync: true);
  final durationEvents = StreamController<Duration>.broadcast(sync: true);
  final completionEvents = StreamController<void>.broadcast(sync: true);
  final errorEvents = StreamController<String>.broadcast(sync: true);
  Duration length = const Duration(seconds: 60);
  Duration current = Duration.zero;
  bool playing = false;
  bool disposed = false;
  double volume = 0;
  int loads = 0;

  @override
  Stream<Duration> get positions => positionEvents.stream;
  @override
  Stream<Duration> get durations => durationEvents.stream;
  @override
  Stream<void> get completions => completionEvents.stream;
  @override
  Stream<String> get errors => errorEvents.stream;
  @override
  Future<void> load(String path) async {
    loads++;
  }

  @override
  Future<Duration?> getDuration() async => length;
  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> resume() async {
    playing = true;
  }

  @override
  Future<void> seek(Duration position) async {
    current = position;
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }

  @override
  Future<void> stop() async {
    playing = false;
    current = Duration.zero;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    playing = false;
    await positionEvents.close();
    await durationEvents.close();
    await completionEvents.close();
    await errorEvents.close();
  }
}

class FakeTts extends GoogleTtsService {
  FakeTts() {
    apiKey = 'test-key';
  }
  final requests = <({String text, AudioVoice voice})>[];
  bool fail = false;
  Completer<Uint8List>? pending;
  CancelToken? token;

  @override
  Future<Uint8List> synthesize(
    String text,
    AudioVoice voice, {
    CancelToken? cancelToken,
  }) async {
    requests.add((text: text, voice: voice));
    token = cancelToken;
    if (fail) throw const AudioRucioException('No se pudo generar la voz.');
    return pending == null ? Uint8List.fromList([1, 2, 3]) : pending!.future;
  }
}

class MemoryAudioCache extends AudioCacheService {
  final files = <String, File>{};
  @override
  Future<File?> find(String key) async => files[key];
  @override
  Future<File> store(
    String key,
    Uint8List bytes, {
    String? protectedPath,
  }) async => files[key] = File('test/$key.mp3');
  @override
  Future<void> trim({Set<String> protectedPaths = const {}}) async {}
  @override
  Future<void> clear() async => files.clear();
  @override
  Future<int> sizeBytes() async => files.length * 3;
}

AudioPage page(int index) => AudioPage(
  startCfi: 'cfi-$index',
  endCfi: 'end-$index',
  nextCfi: index < 2 ? 'cfi-${index + 1}' : null,
  href: 'chapter.xhtml',
  paragraphs: [
    AudioParagraph(
      text: 'Texto del fragmento $index.',
      cfiRange: 'range-$index',
    ),
  ],
);

AudioSession session({
  String? initialCfi = 'cfi-0',
  Future<void> Function(AudioPage)? changed,
}) => AudioSession(
  userId: 'user',
  bookId: 'book',
  initialCfi: initialCfi,
  book: Book(
    id: 'book',
    userId: 'user',
    title: 'El jardín de los caminos',
    author: 'Autora de prueba',
    createdAt: DateTime(2026),
  ),
  loadPage: (cfi) async => page(int.parse((cfi ?? 'cfi-0').split('-').last)),
  onPageChanged: changed ?? (_) async {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Playback', () {
    late FakeAudioPlayback player;
    late FakeTts tts;
    late MemoryAudioCache cache;
    late AudioRucioController audio;

    setUp(() {
      player = FakeAudioPlayback();
      tts = FakeTts();
      cache = MemoryAudioCache();
      audio = AudioRucioController(
        session: session(),
        tts: tts,
        cache: cache,
        player: player,
      );
    });
    tearDown(() async {
      await audio.close();
      audio.dispose();
    });

    test(
      'Pausing and resuming preserve position and do not regenerate audio',
      () async {
        await audio.initialize();
        expect(audio.isPlaying, isTrue);
        player.positionEvents.add(const Duration(seconds: 25));
        await audio.togglePlayback();
        expect(audio.isPlaying, isFalse);
        expect(audio.position.inSeconds, 25);
        await audio.togglePlayback();
        expect(player.playing, isTrue);
        expect(tts.requests.length, 1);
      },
    );

    test(
      'The +15 and -5 controls cross fragment boundaries and reuse cached audio',
      () async {
        await audio.initialize();
        player.positionEvents.add(const Duration(seconds: 59));
        await audio.skip(const Duration(seconds: 15));
        expect(audio.page!.startCfi, 'cfi-1');
        expect(audio.position.inSeconds, 14);
        await audio.seek(const Duration(seconds: 2));
        await audio.skip(const Duration(seconds: -5));
        expect(audio.page!.startCfi, 'cfi-0');
        expect(audio.position.inSeconds, 57);
        expect(tts.requests.length, 2);
        expect(audio.fromCache, isTrue);
        expect(player.playing, isTrue);
      },
    );

    test(
      'Changing voice preserves approximate position and paused state',
      () async {
        await audio.initialize();
        player.positionEvents.add(const Duration(seconds: 30));
        await audio.togglePlayback();
        player.length = const Duration(seconds: 120);
        await audio.changeVoice(AudioVoice.premium);
        expect(tts.requests.last.voice, AudioVoice.premium);
        expect(audio.position.inSeconds, 60);
        expect(audio.isPlaying, isFalse);
        expect(player.playing, isFalse);
        player.length = const Duration(seconds: 60);
        await audio.changeVoice(AudioVoice.standard);
        expect(audio.position.inSeconds, 30);
        expect(tts.requests.length, 2);
        expect(audio.fromCache, isTrue);
      },
    );

    test(
      'A failed generation can be retried without advancing or reporting playback',
      () async {
        tts.fail = true;
        await audio.initialize();
        expect(audio.error, contains('generar'));
        expect(audio.isPlaying, isFalse);
        tts.fail = false;
        await audio.togglePlayback();
        expect(audio.error, isNull);
        expect(audio.page!.startCfi, 'cfi-0');
        expect(audio.isPlaying, isTrue);
      },
    );

    test(
      'Cached fragments play without a Google key and volume persists locally',
      () async {
        final first = page(0);
        await cache.store(
          cache.key('user', 'book', first.text, AudioVoice.standard),
          Uint8List(3),
        );
        tts.apiKey = '';
        await audio.initialize();
        expect(audio.fromCache, isTrue);
        expect(audio.isPlaying, isTrue);
        expect(tts.requests, isEmpty);
        await audio.setVolume(0.25);
        expect(player.volume, 0.25);
        expect(
          (await SharedPreferences.getInstance()).getDouble(
            'audiorucio.volume',
          ),
          0.25,
        );
      },
    );

    test(
      'Closing during generation cancels the request and never starts late playback',
      () async {
        tts.pending = Completer<Uint8List>();
        final initialized = audio.initialize();
        while (tts.requests.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        await audio.close();
        expect(tts.token!.isCancelled, isTrue);
        tts.pending!.complete(Uint8List(3));
        await initialized;
        expect(player.loads, 0);
        expect(player.disposed, isTrue);
        expect(player.playing, isFalse);
      },
    );

    test(
      'Reopening restores local time only at the same EPUB position',
      () async {
        await audio.initialize();
        player.positionEvents.add(const Duration(seconds: 23));
        await audio.close();
        final resumed = AudioRucioController(
          session: session(),
          tts: tts,
          cache: cache,
          player: FakeAudioPlayback(),
        );
        await resumed.initialize();
        expect(resumed.position.inSeconds, 23);
        await resumed.close();
        resumed.dispose();
        final elsewhere = AudioRucioController(
          session: session(initialCfi: 'cfi-1'),
          tts: tts,
          cache: cache,
          player: FakeAudioPlayback(),
        );
        await elsewhere.initialize();
        expect(elsewhere.position, Duration.zero);
        await elsewhere.close();
        elsewhere.dispose();
      },
    );

    test(
      'The end of the book stops playback and rewind works afterwards',
      () async {
        await audio.initialize();
        await audio.skip(const Duration(seconds: 180));
        expect(audio.page!.startCfi, 'cfi-2');
        expect(audio.finished, isTrue);
        expect(audio.isPlaying, isFalse);
        await audio.skip(const Duration(seconds: -5));
        expect(audio.position.inSeconds, 55);
        expect(audio.finished, isFalse);
        await audio.togglePlayback();
        expect(audio.position.inSeconds, 55);
      },
    );
  });

  test(
    'Cache is isolated by user, book, voice and text and evicts the oldest unprotected audio',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'audiorucio_test_',
      );
      final cache = AudioCacheService(directory: directory, maxBytes: 8);
      try {
        final a = cache.key('a', 'book', 'text', AudioVoice.standard);
        final b = cache.key('b', 'book', 'text', AudioVoice.standard);
        final premium = cache.key('a', 'book', 'text', AudioVoice.premium);
        expect(
          {
            a,
            b,
            premium,
            cache.key('a', 'other', 'text', AudioVoice.standard),
            cache.key('a', 'book', 'other', AudioVoice.standard),
          }.length,
          5,
        );
        final first = await cache.store(a, Uint8List(4));
        await first.setLastModified(DateTime(2020));
        await cache.store(b, Uint8List(4));
        final third = await cache.store(premium, Uint8List(4));
        expect(await first.exists(), isFalse);
        expect(await third.exists(), isTrue);
        expect(await cache.sizeBytes(), 8);
        await cache.clear();
        expect(await cache.sizeBytes(), 0);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'Google requests use the selected voice, MP3 and a header key without exposing it in errors',
    () async {
      final dio = Dio();
      late RequestOptions request;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'audioContent': base64Encode([1, 2, 3]),
                },
              ),
            );
          },
        ),
      );
      final tts = GoogleTtsService(dio: dio)..apiKey = 'private-test-key';
      expect(await tts.synthesize('Árbol.', AudioVoice.premium), [1, 2, 3]);
      expect(request.data['voice']['name'], 'es-ES-Chirp3-HD-Autonoe');
      expect(request.data['audioConfig'], {'audioEncoding': 'MP3'});
      expect(request.headers['X-Goog-Api-Key'], 'private-test-key');
      expect(request.uri.toString(), isNot(contains('private-test-key')));
      dio.interceptors.clear();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 403),
              ),
            );
          },
        ),
      );
      await expectLater(
        tts.synthesize('Texto.', AudioVoice.standard),
        throwsA(
          isA<AudioRucioException>().having(
            (error) => error.message,
            'message',
            allOf(contains('acceso'), isNot(contains('private-test-key'))),
          ),
        ),
      );
      await expectLater(
        tts.synthesize('á' * 2501, AudioVoice.standard),
        throwsA(isA<AudioRucioException>()),
      );
    },
  );

  for (final size in [const Size(1280, 800), const Size(800, 600)]) {
    testWidgets(
      'Desktop player renders and controls playback at ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final player = FakeAudioPlayback();
        const preview = bool.fromEnvironment('AUDIORUCIO_PREVIEW');
        if (preview) {
          final font = await tester.runAsync(
            () => File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
          );
          await (FontLoader(
            'Preview',
          )..addFont(Future.value(ByteData.sublistView(font!)))).load();
          await tester.runAsync(
            () =>
                (FontLoader('MaterialIcons')..addFont(
                      rootBundle.load('fonts/MaterialIcons-Regular.otf'),
                    ))
                    .load(),
          );
        }
        var exited = false;
        final key = GlobalKey();
        final audioSession = session();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              googleTtsServiceProvider.overrideWithValue(FakeTts()),
              audioCacheServiceProvider.overrideWithValue(MemoryAudioCache()),
              audioPlaybackFactoryProvider.overrideWithValue(() => player),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                theme: ThemeData(
                  fontFamily: preview ? 'Preview' : null,
                  useMaterial3: true,
                  brightness: Brightness.dark,
                  colorSchemeSeed: const Color(0xFFF2A65A),
                ),
                home: AudioRucioPlayer(
                  session: audioSession,
                  onExit: () => exited = true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Audiorucio'), findsOneWidget);
        expect(find.text('El jardín de los caminos'), findsWidgets);
        expect(find.text('Texto del fragmento 0.'), findsOneWidget);
        expect(player.playing, isTrue);
        Future<void> capture(String path) async {
          if (!preview || size.width != 1280) return;
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory('build').create(recursive: true);
            await File(path).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('build/audiorucio-preview.png');
        await tester.tap(find.byIcon(Icons.pause_rounded));
        await tester.pumpAndSettle();
        expect(player.playing, isFalse);
        await tester.tap(find.byTooltip('Adelantar 15 segundos'));
        await tester.pumpAndSettle();
        expect(player.current.inSeconds, 15);
        await tester.tap(find.byTooltip('Atrasar 5 segundos'));
        await tester.pumpAndSettle();
        expect(player.current.inSeconds, 10);
        await tester.tap(find.byTooltip('Consumo mensual'));
        await tester.pumpAndSettle();
        expect(
          find.text('Coste estimado tras el tramo gratuito'),
          findsOneWidget,
        );
        await capture('build/audiorucio-usage-preview.png');
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Volver al libro'));
        await tester.pumpAndSettle();
        expect(exited, isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
