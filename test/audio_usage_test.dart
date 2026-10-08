import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rucio_flutter/models/audio_page.dart';
import 'package:rucio_flutter/providers/audiorucio_provider.dart';
import 'package:rucio_flutter/services/audio_usage_service.dart';
import 'package:rucio_flutter/services/google_tts_service.dart';
import 'package:rucio_flutter/widgets/audio_usage_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audiorucio_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late AudioUsageService usage;
  var widgetOwnsUsage = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 10, 8, 12);
    usage = AudioUsageService(now: () => now);
    widgetOwnsUsage = false;
  });
  tearDown(() {
    if (!widgetOwnsUsage) usage.dispose();
  });

  test(
    'Unicode characters, spaces and newlines persist without text or keys',
    () async {
      final request = await usage.begin('Á 😀\n', AudioVoice.premium);
      expect(request.characters, 4);
      await usage.finish(request, generated: true);
      final reloaded = AudioUsageService(now: () => now);
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(reloaded.totals('2026-10', AudioVoice.premium).characters, 4);
      expect(reloaded.trackedSince, now);
      final stored = (await SharedPreferences.getInstance()).getString(
        AudioUsageService.preferencesKey,
      )!;
      expect(stored, isNot(contains('Á')));
      expect(stored, isNot(contains('key')));
    },
  );

  test(
    'Free allowances and paid characters are calculated separately per voice',
    () {
      for (final voice in AudioVoice.values) {
        expect(const AudioUsageTotals().estimatedUsd(voice), 0);
        expect(
          AudioUsageTotals(
            characters: voice.freeCharacters,
          ).estimatedUsd(voice),
          0,
        );
        final totals = AudioUsageTotals(
          characters: voice.freeCharacters + 250000,
        );
        expect(
          totals.estimatedUsd(voice),
          voice == AudioVoice.standard ? 1 : 7.5,
        );
        expect(
          totals.listPriceUsd(voice),
          voice == AudioVoice.standard ? 17 : 37.5,
        );
      }
    },
  );

  test(
    'Concurrent requests survive rollover and keep their original month',
    () async {
      now = DateTime(2026, 12, 31, 23, 59, 59);
      final old = await usage.begin('Antes', AudioVoice.standard);
      now = DateTime(2027, 1, 1);
      final requests = await Future.wait([
        for (var i = 0; i < 20; i++) usage.begin('Después', AudioVoice.premium),
      ]);
      await Future.wait([
        usage.finish(old, generated: true),
        for (final request in requests) usage.finish(request, generated: true),
      ]);
      expect(usage.totals('2026-12', AudioVoice.standard).characters, 5);
      expect(usage.totals('2027-01', AudioVoice.premium).characters, 140);
      expect(
        usage.totals('2027-01', AudioVoice.premium).unconfirmedCharacters,
        0,
      );
      expect(usage.months, ['2027-01', '2026-12']);
    },
  );

  test('Interrupted requests remain unconfirmed after restart', () async {
    await usage.begin('Sin respuesta', AudioVoice.premium);
    final rejected = await usage.begin('Rechazada', AudioVoice.standard);
    await usage.finish(rejected, generated: false);
    final reloaded = AudioUsageService(now: () => now);
    addTearDown(reloaded.dispose);
    await reloaded.initialize();
    expect(reloaded.totals('2026-10', AudioVoice.premium).characters, 0);
    expect(
      reloaded.totals('2026-10', AudioVoice.premium).unconfirmedCharacters,
      13,
    );
    expect(
      reloaded.totals('2026-10', AudioVoice.standard).unconfirmedCharacters,
      0,
    );
  });

  test(
    'Only cloud generation counts; replay, cache hits and clearing cache do not',
    () async {
      final dio = Dio();
      var calls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
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
      final tts = GoogleTtsService(dio: dio, usage: usage)..apiKey = 'secret';
      final audio = AudioRucioController(
        session: AudioSession(
          userId: 'user',
          bookId: 'book',
          initialCfi: 'cfi-2',
          loadPage: (_) async => fixtures.page(2),
          onPageChanged: (_) async {},
        ),
        tts: tts,
        cache: fixtures.MemoryAudioCache(),
        player: fixtures.FakeAudioPlayback(),
      );
      addTearDown(() async {
        await audio.close();
        audio.dispose();
      });
      await audio.initialize();
      await audio.togglePlayback();
      await audio.togglePlayback();
      await audio.changeVoice(AudioVoice.premium);
      await audio.changeVoice(AudioVoice.standard);
      final length = fixtures.page(2).text.runes.length;
      expect(calls, 2);
      expect(usage.totals('2026-10', AudioVoice.standard).characters, length);
      expect(usage.totals('2026-10', AudioVoice.premium).characters, length);
      await audio.clearCache();
      expect(usage.totals('2026-10', AudioVoice.standard).characters, length);
      await audio.togglePlayback();
      expect(calls, 3);
      expect(
        usage.totals('2026-10', AudioVoice.standard).characters,
        length * 2,
      );
    },
  );

  test(
    'Preloaded audio counts once and entering paused has no consumption',
    () async {
      final dio = Dio();
      final texts = <String>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            texts.add(options.data['input']['text'] as String);
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
      final player = fixtures.FakeAudioPlayback();
      final audio = AudioRucioController(
        session: fixtures.session(),
        tts: GoogleTtsService(dio: dio, usage: usage)..apiKey = 'fixture',
        cache: fixtures.MemoryAudioCache(),
        player: player,
      );
      addTearDown(() async {
        await audio.close();
        audio.dispose();
      });
      await audio.initialize();
      expect(texts, isEmpty);
      await audio.togglePlayback();
      for (
        var i = 0;
        i < 100 &&
            usage.totals('2026-10', AudioVoice.standard).characters <
                fixtures.page(0).text.runes.length +
                    fixtures.page(1).text.runes.length;
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      final total =
          fixtures.page(0).text.runes.length +
          fixtures.page(1).text.runes.length;
      expect(texts, [fixtures.page(0).text, fixtures.page(1).text]);
      expect(usage.totals('2026-10', AudioVoice.standard).characters, total);
      await audio.togglePlayback();
      await audio.skip(const Duration(seconds: 61));
      expect(audio.page!.startCfi, 'cfi-1');
      expect(texts.length, 2);
      expect(usage.totals('2026-10', AudioVoice.standard).characters, total);
    },
  );

  for (final status in [403, 429, 500, null]) {
    test('HTTP $status distinguishes rejection from unknown billing', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: status == null
                    ? DioExceptionType.receiveTimeout
                    : DioExceptionType.badResponse,
                response: status == null
                    ? null
                    : Response(requestOptions: options, statusCode: status),
              ),
            );
          },
        ),
      );
      final tts = GoogleTtsService(dio: dio, usage: usage)..apiKey = 'secret';
      await expectLater(
        tts.synthesize('Texto', AudioVoice.standard),
        throwsA(isA<AudioRucioException>()),
      );
      final totals = usage.totals('2026-10', AudioVoice.standard);
      expect(totals.characters, 0);
      expect(
        totals.unconfirmedCharacters,
        status == 403 || status == 429 ? 0 : 5,
      );
    });
  }

  test(
    'A cancelled request in flight is not silently considered free',
    () async {
      final dio = Dio();
      final started = Completer<void>();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            started.complete();
            options.cancelToken!.whenCancel.then(
              (error) => handler.reject(error),
            );
          },
        ),
      );
      final tts = GoogleTtsService(dio: dio, usage: usage)..apiKey = 'secret';
      final token = CancelToken();
      final result = tts.synthesize(
        'Texto',
        AudioVoice.premium,
        cancelToken: token,
      );
      final assertion = expectLater(result, throwsA(isA<DioException>()));
      await started.future;
      token.cancel();
      await assertion;
      expect(
        usage.totals('2026-10', AudioVoice.premium).unconfirmedCharacters,
        5,
      );
    },
  );

  test(
    'Corrupt usage data blocks generation instead of resetting the bill',
    () async {
      SharedPreferences.setMockInitialValues({
        AudioUsageService.preferencesKey: 'invalid',
      });
      final dio = Dio();
      var calls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (_, handler) {
            calls++;
          },
        ),
      );
      final tts = GoogleTtsService(dio: dio, usage: usage)..apiKey = 'secret';
      await expectLater(
        tts.synthesize('Texto', AudioVoice.standard),
        throwsA(isA<AudioRucioException>()),
      );
      expect(calls, 0);
      expect(usage.error, isNotNull);
    },
  );

  test(
    'A successful response counts even if the returned audio is unusable',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(requestOptions: options, data: {'audioContent': ''}),
            );
          },
        ),
      );
      final tts = GoogleTtsService(dio: dio, usage: usage)..apiKey = 'secret';
      await expectLater(
        tts.synthesize('Texto', AudioVoice.premium),
        throwsA(isA<AudioRucioException>()),
      );
      expect(usage.totals('2026-10', AudioVoice.premium).characters, 5);
      expect(
        usage.totals('2026-10', AudioVoice.premium).unconfirmedCharacters,
        0,
      );
    },
  );

  test(
    'Validation errors and cancellation before sending do not count',
    () async {
      final tts = GoogleTtsService(usage: usage)..apiKey = '';
      await expectLater(
        tts.synthesize('Texto', AudioVoice.standard),
        throwsA(isA<AudioRucioException>()),
      );
      tts.apiKey = 'secret';
      await expectLater(
        tts.synthesize('á' * 2501, AudioVoice.standard),
        throwsA(isA<AudioRucioException>()),
      );
      final token = CancelToken()..cancel();
      await expectLater(
        tts.synthesize('Texto', AudioVoice.standard, cancelToken: token),
        throwsA(isA<DioException>()),
      );
      expect(usage.totals('2026-10', AudioVoice.standard).characters, 0);
      expect(
        usage.totals('2026-10', AudioVoice.standard).unconfirmedCharacters,
        0,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          AudioUsageService.preferencesKey,
        ),
        isNull,
      );
    },
  );

  for (final size in [const Size(1280, 800), const Size(800, 600)]) {
    testWidgets('Monthly spending and history fit at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        now = DateTime(2026, 9, 30);
        final old = await usage.begin('Anterior mes', AudioVoice.standard);
        await usage.finish(old, generated: true);
        now = DateTime(2026, 10, 8);
        final current = await usage.begin('Este mes', AudioVoice.premium);
        await usage.finish(current, generated: true);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [audioUsageServiceProvider.overrideWith((ref) => usage)],
          child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: const Scaffold(body: AudioUsageDialog()),
          ),
        ),
      );
      widgetOwnsUsage = true;
      await tester.pumpAndSettle();
      expect(find.text('Consumo mensual'), findsOneWidget);
      expect(find.text('Octubre 2026'), findsOneWidget);
      expect(find.text('8 caracteres generados'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Septiembre 2026').last);
      await tester.pumpAndSettle();
      expect(find.text('12 caracteres generados'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
