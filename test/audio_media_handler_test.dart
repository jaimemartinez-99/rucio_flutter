import 'dart:async';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rucio_flutter/providers/audiorucio_provider.dart';
import 'package:rucio_flutter/services/audio_media_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audiorucio_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fixtures.FakeAudioPlayback player;
  late fixtures.FakeTts tts;
  late AudioRucioController audio;
  late AudioMediaHandler handler;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    player = fixtures.FakeAudioPlayback();
    tts = fixtures.FakeTts();
    audio = AudioRucioController(
      session: fixtures.session(),
      tts: tts,
      cache: fixtures.MemoryAudioCache(),
      player: player,
    );
    handler = AudioMediaHandler(artwork: (_) async => Uri.file('/cover.jpg'));
    handler.attach(audio);
    await audio.initialize();
  });

  tearDown(() async {
    await audio.close();
    audio.dispose();
  });

  test(
    'Media sessions open idle, publish book metadata and expose the requested controls',
    () async {
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(tts.requests, isEmpty);
      expect(handler.mediaItem.value!.title, 'El jardín de los caminos');
      expect(handler.mediaItem.value!.artUri, Uri.file('/cover.jpg'));
      await handler.play();
      expect(handler.playbackState.value.playing, isTrue);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      expect(
        handler.playbackState.value.controls.map((control) => control.action),
        [
          MediaAction.rewind,
          MediaAction.pause,
          MediaAction.fastForward,
          MediaAction.stop,
        ],
      );
      expect(handler.playbackState.value.controls.first.label, contains('5'));
      expect(handler.playbackState.value.controls[2].label, contains('15'));
      await handler.pause();
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.controls[1].action, MediaAction.play);
    },
  );

  test(
    'Remote rewind and fast forward use 5 and 15 seconds and cross pages',
    () async {
      await handler.play();
      player.positionEvents.add(const Duration(seconds: 50));
      await handler.rewind();
      expect(audio.position, const Duration(seconds: 45));
      await handler.fastForward();
      expect(audio.page!.startCfi, 'cfi-1');
      expect(audio.position, Duration.zero);
      expect(handler.playbackState.value.playing, isTrue);
      await handler.pause();
      await handler.rewind();
      expect(audio.page!.startCfi, 'cfi-0');
      expect(audio.position, const Duration(seconds: 55));
      expect(handler.playbackState.value.playing, isFalse);
    },
  );

  test(
    'Pause during generation prevents late autoplay and keeps the generated audio for resume',
    () async {
      tts.pending = Completer<Uint8List>();
      final playing = handler.play();
      while (tts.requests.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(handler.playbackState.value.playing, isTrue);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.buffering,
      );
      await handler.pause();
      tts.pending!.complete(Uint8List(3));
      await playing;
      expect(player.playing, isFalse);
      expect(handler.playbackState.value.playing, isFalse);
      await handler.play();
      expect(player.playing, isTrue);
      expect(
        tts.requests
            .where((request) => request.text == fixtures.page(0).text)
            .length,
        1,
      );
    },
  );

  test(
    'Stop removes the media notification without losing position; closing releases the session',
    () async {
      await handler.play();
      player.positionEvents.add(const Duration(seconds: 23));
      await handler.stop();
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(player.playing, isFalse);
      expect(audio.position.inSeconds, 23);
      await handler.play();
      expect(audio.position.inSeconds, 23);
      await audio.close();
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(handler.mediaItem.value, isNull);
      await handler.fastForward();
      expect(player.disposed, isTrue);
    },
  );
}
