import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class AudioPlayback {
  Stream<Duration> get positions;
  Stream<Duration> get durations;
  Stream<void> get completions;
  Stream<String> get errors;
  Future<void> load(String path);
  Future<void> resume();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<Duration?> getDuration();
  Future<void> dispose();
}

class DesktopAudioPlayback implements AudioPlayback {
  DesktopAudioPlayback() {
    _events = _player.eventStream.listen(
      (_) {},
      onError: (Object error) => _errors.add('No se pudo reproducir el audio.'),
    );
  }

  final AudioPlayer _player = AudioPlayer();
  final _errors = StreamController<String>.broadcast();
  late final StreamSubscription<AudioEvent> _events;

  @override
  Stream<Duration> get positions => _player.onPositionChanged;
  @override
  Stream<Duration> get durations => _player.onDurationChanged;
  @override
  Stream<void> get completions => _player.onPlayerComplete;
  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> load(String path) async {
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setSourceDeviceFile(path);
  }

  @override
  Future<void> resume() => _player.resume();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.release();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Future<Duration?> getDuration() => _player.getDuration();
  @override
  Future<void> dispose() async {
    await _events.cancel();
    await _player.dispose();
    await _errors.close();
  }
}

final audioPlaybackFactoryProvider = Provider<AudioPlayback Function()>((ref) {
  return DesktopAudioPlayback.new;
});
