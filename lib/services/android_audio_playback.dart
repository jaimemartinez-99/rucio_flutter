import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart' as ja;

import 'audio_playback.dart';

class AndroidAudioPlayback implements AudioPlayback {
  AndroidAudioPlayback() {
    _subscriptions.addAll([
      _player.processingStateStream.distinct().listen((state) {
        if (state == ja.ProcessingState.completed) _completions.add(null);
      }),
      _player.errorStream.listen(
        (_) => _errors.add('No se pudo reproducir el audio.'),
      ),
    ]);
  }

  final _player = ja.AudioPlayer(handleInterruptions: false);
  final _completions = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final _interruptions = StreamController<bool>.broadcast();
  Future<void>? _configured;

  Stream<bool> get interruptions => _interruptions.stream;

  Future<void> _configure() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    _subscriptions.addAll([
      session.interruptionEventStream.listen((event) {
        if (event.begin) _interruptions.add(true);
      }),
      session.becomingNoisyEventStream.listen((_) => _interruptions.add(true)),
    ]);
  }

  @override
  Stream<Duration> get positions => _player.positionStream;
  @override
  Stream<Duration> get durations =>
      _player.durationStream.where((value) => value != null).cast<Duration>();
  @override
  Stream<void> get completions => _completions.stream;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Future<void> load(String path) async {
    await (_configured ??= _configure());
    await _player.setFilePath(path);
  }

  @override
  Future<void> resume() async {
    unawaited(
      _player.play().catchError((Object error) {
        if (!_errors.isClosed) _errors.add('No se pudo reproducir el audio.');
      }),
    );
  }

  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Future<Duration?> getDuration() async => _player.duration;
  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _completions.close();
    await _errors.close();
    await _interruptions.close();
  }
}
