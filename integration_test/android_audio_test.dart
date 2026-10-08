import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rucio_flutter/models/audio_page.dart';
import 'package:rucio_flutter/models/book.dart';
import 'package:rucio_flutter/providers/audiorucio_provider.dart';
import 'package:rucio_flutter/services/audio_cache_service.dart';
import 'package:rucio_flutter/services/audio_media_handler.dart';
import 'package:rucio_flutter/services/google_tts_service.dart';
import 'package:rucio_flutter/services/reader_content_loader.dart';
import 'package:rucio_flutter/services/reader_webview.dart';
import 'package:rucio_flutter/widgets/audiorucio_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'desktop_audio_test.dart' as fixtures;

class _SilentTts extends GoogleTtsService {
  _SilentTts() {
    apiKey = 'fixture';
  }
  @override
  Future<Uint8List> synthesize(
    String text,
    AudioVoice voice, {
    CancelToken? cancelToken,
  }) async => fixtures.silentWave();
}

class _TestMediaHandler extends AudioMediaHandler {
  final paused = Completer<void>();
  final rewound = Completer<void>();
  final forwarded = Completer<void>();
  final resumed = Completer<void>();
  final stopped = Completer<void>();
  @override
  Future<void> pause() async {
    await super.pause();
    if (!paused.isCompleted) paused.complete();
  }

  @override
  Future<void> rewind() async {
    await super.rewind();
    if (!rewound.isCompleted) rewound.complete();
  }

  @override
  Future<void> fastForward() async {
    await super.fastForward();
    if (!forwarded.isCompleted) forwarded.complete();
  }

  @override
  Future<void> play() async {
    await super.play();
    if (!resumed.isCompleted) resumed.complete();
  }

  @override
  Future<void> stop() async {
    await super.stop();
    if (!stopped.isCompleted) stopped.complete();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android keeps reading in the background and responds to native media controls',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final handler = await AudioService.init(
        builder: _TestMediaHandler.new,
        config: AudioMediaHandler.configuration,
      );
      final directory = await Directory.systemTemp.createTemp(
        'audiorucio_android_',
      );
      final body = List.generate(
        100,
        (i) =>
            '<p>Párrafo $i. ${'Esta historia continúa con árboles y caminos que podemos escuchar. ' * 12}</p>',
      ).join();
      final file = await File(
        '${directory.path}/fixture.epub',
      ).writeAsBytes(fixtures.fixtureEpub(body: body));
      final client = SupabaseClient('https://fixture.example', 'fixture');
      final content = await ReaderContentLoader(
        client: client,
        database: client,
      ).loadCachedEpub(file.path);
      final web = ReaderWebView.create();
      final pending = <int, Completer<AudioPage?>>{};
      final ready = Completer<void>();
      final located = Completer<Map<String, dynamic>>();
      var id = 0;
      final messages = web.messages.listen((event) {
        if (event.channel == 'ReaderReady' && !ready.isCompleted) {
          ready.complete();
        }
        if (event.channel == 'AudioPage') {
          final data = jsonDecode(event.message) as Map<String, dynamic>;
          final response = pending.remove(data['requestId']);
          if (response != null) {
            if (data['error'] != null) {
              response.completeError(StateError(data['error'] as String));
            } else {
              response.complete(
                data['page'] == null
                    ? null
                    : AudioPage.fromJson(data['page'] as Map<String, dynamic>),
              );
            }
          }
        }
        if (event.channel == 'Toc' &&
            event.message.startsWith('{') &&
            !located.isCompleted) {
          located.complete(jsonDecode(event.message) as Map<String, dynamic>);
        }
      });
      final sessionView = ValueNotifier<AudioSession?>(null);
      final changed = <String>[];
      final advanced = Completer<void>();
      AudioRucioController? audio;
      Future<void> wait(Future<void> future) =>
          future.timeout(const Duration(seconds: 50));
      try {
        await web.initialize();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              audioMediaHandlerProvider.overrideWithValue(handler),
              googleTtsServiceProvider.overrideWithValue(_SilentTts()),
              audioCacheServiceProvider.overrideWithValue(
                AudioCacheService(
                  directory: Directory('${directory.path}/audio'),
                ),
              ),
            ],
            child: MaterialApp(
              theme: ThemeData.dark(useMaterial3: true),
              home: Scaffold(
                body: ValueListenableBuilder<AudioSession?>(
                  valueListenable: sessionView,
                  builder: (context, session, _) => Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(child: web.buildView()),
                      if (session != null)
                        Positioned.fill(
                          child: AudioRucioPlayer(
                            session: session,
                            onExit: () => sessionView.value = null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await web.loadHtml(content.html);
        await tester.runAsync(() => wait(ready.future));
        await web.runJavaScript(
          "(async function(){setStyles('body,p { font-size: 18px !important; line-height: 1.7 !important; } body { padding: 10px 12px !important; }'); await displayAfterLayout(0); postToFlutter('Toc',JSON.stringify(rendition.currentLocation()));})()",
        );
        final location = await tester.runAsync(
          () => located.future.timeout(const Duration(seconds: 20)),
        );
        final session = AudioSession(
          userId: 'fixture',
          bookId: 'android',
          initialCfi: location!['start']['cfi'] as String,
          book: Book(
            id: 'android',
            userId: 'fixture',
            title: 'Prueba de Audiorucio',
            author: 'Rucio',
            createdAt: DateTime(2026),
          ),
          loadPage: (cfi) async {
            final request = ++id;
            final response = Completer<AudioPage?>();
            pending[request] = response;
            await web.runJavaScript(
              'requestAudioPage($request, ${jsonEncode(cfi)})',
            );
            return response.future.timeout(const Duration(seconds: 40));
          },
          onPageChanged: (page) async {
            changed.add(page.startCfi);
            if (changed.length >= 4 && !advanced.isCompleted) {
              advanced.complete();
            }
          },
        );
        sessionView.value = session;
        for (
          var attempt = 0;
          attempt < 100 && find.text('Texto de la lectura').evaluate().isEmpty;
          attempt++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AudioRucioPlayer)),
        );
        final controller = container.read(audioRucioProvider(session));
        audio = controller;
        var previousState = '';
        controller.addListener(() {
          final state =
              '${controller.isBusy}:${controller.wantsPlayback}:${controller.isPlaying}:${controller.page?.startCfi}:${controller.error}';
          if (state != previousState) {
            previousState = state;
            debugPrint('AUDIORUCIO_CONTROLLER: $state');
          }
        });
        await tester.runAsync(() async {
          while (controller.isBusy) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        });
        expect(controller.isPlaying, isFalse);
        expect(controller.page!.startCfi, location['start']['cfi']);
        expect(controller.page!.endCfi, location['end']['cfi']);
        await controller.setVolume(0);
        await tester.runAsync(() async {
          await controller.play();
          debugPrint('AUDIORUCIO_TEST_READY');
          await wait(advanced.future);
          expect(
            WidgetsBinding.instance.lifecycleState,
            AppLifecycleState.paused,
          );
          expect(changed.toSet().length, greaterThanOrEqualTo(4));
          debugPrint('AUDIORUCIO_AUTO_ADVANCED');
          await wait(handler.paused.future);
          expect(controller.isPlaying, isFalse);
          debugPrint('AUDIORUCIO_PAUSED');
          await wait(handler.rewound.future);
          expect(controller.isPlaying, isFalse);
          debugPrint('AUDIORUCIO_REWOUND');
          await wait(handler.forwarded.future);
          expect(controller.isPlaying, isFalse);
          debugPrint('AUDIORUCIO_FORWARDED');
          await wait(handler.resumed.future);
          expect(controller.isPlaying, isTrue);
          debugPrint('AUDIORUCIO_RESUMED');
          await wait(handler.stopped.future);
          expect(controller.isPlaying, isFalse);
          expect(
            handler.playbackState.value.processingState,
            AudioProcessingState.idle,
          );
          debugPrint('AUDIORUCIO_STOPPED');
          while (WidgetsBinding.instance.lifecycleState !=
              AppLifecycleState.resumed) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        });
        expect(tester.takeException(), isNull);
      } finally {
        await audio?.close();
        await tester.pumpWidget(const SizedBox());
        await messages.cancel();
        await web.dispose();
        await content.dispose();
        await client.dispose();
        sessionView.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isAndroid,
  );
}
