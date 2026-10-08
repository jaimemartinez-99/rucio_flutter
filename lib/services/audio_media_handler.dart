import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/book.dart';
import '../providers/audiorucio_provider.dart';

class AudioMediaHandler extends BaseAudioHandler {
  AudioMediaHandler({Future<Uri?> Function(Book)? artwork})
    : _artwork = artwork ?? _saveArtwork;

  final Future<Uri?> Function(Book) _artwork;
  AudioRucioController? _controller;
  Uri? _artUri;
  bool _started = false;
  bool _stopped = false;

  static const configuration = AudioServiceConfig(
    androidNotificationChannelId: 'com.rucio.audiorucio.playback',
    androidNotificationChannelName: 'Audiorucio',
    androidNotificationChannelDescription: 'Lectura de libros en segundo plano',
    androidNotificationIcon: 'drawable/ic_audiorucio',
    androidStopForegroundOnPause: false,
    rewindInterval: Duration(seconds: 5),
    fastForwardInterval: Duration(seconds: 15),
  );

  static Future<AudioMediaHandler> initialize() =>
      AudioService.init(builder: AudioMediaHandler.new, config: configuration);

  void attach(AudioRucioController controller) {
    if (_controller == controller) return;
    final previous = _controller;
    if (previous != null) {
      detach(previous);
      unawaited(previous.close());
    }
    _controller = controller;
    _started = false;
    _stopped = false;
    _artUri = null;
    controller.addListener(_publish);
    _publish();
    final book = controller.session.book;
    if (book != null) {
      unawaited(() async {
        try {
          final art = await _artwork(book);
          if (_controller != controller) return;
          _artUri = art;
          _publish();
        } catch (_) {}
      }());
    }
  }

  void detach(AudioRucioController controller) {
    if (_controller != controller) return;
    controller.removeListener(_publish);
    _controller = null;
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle),
    );
    mediaItem.add(null);
  }

  void _publish() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.isClosed) {
      detach(controller);
      return;
    }
    if (controller.wantsPlayback) {
      _started = true;
      _stopped = false;
    }
    final item = MediaItem(
      id: controller.session.bookId,
      title: controller.session.book?.title ?? 'Tu libro',
      artist: controller.session.book?.author,
      album: 'Audiorucio',
      duration: controller.duration > Duration.zero
          ? controller.duration
          : null,
      artUri: _artUri,
    );
    final previous = mediaItem.value;
    if (previous?.id != item.id ||
        previous?.duration != item.duration ||
        previous?.artUri != item.artUri) {
      mediaItem.add(item);
    }
    final active = _started && !_stopped && !controller.finished;
    playbackState.add(
      PlaybackState(
        controls: [
          const MediaControl(
            androidIcon: 'drawable/ic_rewind_5',
            label: 'Retroceder 5 segundos',
            action: MediaAction.rewind,
          ),
          controller.wantsPlayback ? MediaControl.pause : MediaControl.play,
          const MediaControl(
            androidIcon: 'drawable/ic_forward_15',
            label: 'Avanzar 15 segundos',
            action: MediaAction.fastForward,
          ),
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {
          MediaAction.seek,
          MediaAction.play,
          MediaAction.pause,
          MediaAction.rewind,
          MediaAction.fastForward,
          MediaAction.stop,
        },
        processingState: !active
            ? AudioProcessingState.idle
            : controller.error != null
            ? AudioProcessingState.error
            : controller.isBusy
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: active && controller.wantsPlayback,
        updatePosition: controller.position,
        bufferedPosition: controller.duration,
        errorCode: controller.error == null ? null : 1,
        errorMessage: controller.error,
      ),
    );
  }

  Future<void> _whenReady(
    Future<void> Function(AudioRucioController) action,
  ) async {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    if (controller.isBusy) {
      final ready = Completer<void>();
      void changed() {
        if ((!controller.isBusy || controller.isClosed) && !ready.isCompleted) {
          ready.complete();
        }
      }

      controller.addListener(changed);
      try {
        changed();
        await ready.future.timeout(const Duration(seconds: 30));
      } on TimeoutException {
        return;
      } finally {
        controller.removeListener(changed);
      }
    }
    if (_controller == controller && !controller.isClosed) {
      await action(controller);
    }
  }

  @override
  Future<void> play() => _whenReady((controller) => controller.play());
  @override
  Future<void> pause() async {
    await _controller?.pause();
  }

  @override
  Future<void> rewind() =>
      _whenReady((controller) => controller.skip(const Duration(seconds: -5)));
  @override
  Future<void> fastForward() =>
      _whenReady((controller) => controller.skip(const Duration(seconds: 15)));
  @override
  Future<void> seek(Duration position) =>
      _whenReady((controller) => controller.seek(position));
  @override
  Future<void> stop() async {
    await pause();
    _stopped = true;
    _publish();
  }

  @override
  Future<void> onNotificationDeleted() => stop();
  @override
  Future<void> onTaskRemoved() async {
    await _controller?.close();
  }

  static Future<Uri?> _saveArtwork(Book book) async {
    final cover = book.coverUrl;
    if (cover == null || !cover.startsWith('data:image/')) return null;
    final comma = cover.indexOf(',');
    if (comma < 0) return null;
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/audiorucio_artwork',
    );
    await directory.create(recursive: true);
    final key = sha256.convert(utf8.encode('${book.userId}:${book.id}:$cover'));
    final file = File(
      '${directory.path}/$key.${cover.startsWith('data:image/png') ? 'png' : 'jpg'}',
    );
    if (!await file.exists()) {
      await file.writeAsBytes(
        base64Decode(cover.substring(comma + 1)),
        flush: true,
      );
    }
    return file.uri;
  }
}

final audioMediaHandlerProvider = Provider<AudioMediaHandler?>((ref) => null);
