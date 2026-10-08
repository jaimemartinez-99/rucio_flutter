import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/audio_page.dart';
import '../models/book.dart';
import '../services/audio_cache_service.dart';
import '../services/audio_playback.dart';
import '../services/google_tts_service.dart';

class AudioSession {
  const AudioSession({
    required this.userId,
    required this.bookId,
    required this.initialCfi,
    required this.loadPage,
    required this.onPageChanged,
    this.book,
    this.readerCfi,
  });

  final String userId;
  final String bookId;
  final String? initialCfi;
  final Book? book;
  final String? Function()? readerCfi;
  final Future<AudioPage?> Function(String? cfi) loadPage;
  final Future<void> Function(AudioPage page) onPageChanged;
}

class AudioRucioController extends ChangeNotifier {
  AudioRucioController({
    required this.session,
    required this.tts,
    required this.cache,
    required this.player,
  }) {
    _subscriptions.addAll([
      player.positions.listen((value) {
        if (_busy || _closed) return;
        position = value;
        _saveSoon();
        notifyListeners();
      }),
      player.durations.listen((value) {
        if (_closed || value <= Duration.zero) return;
        duration = value;
        notifyListeners();
      }),
      player.completions.listen((_) {
        if (!_closed && isPlaying) {
          _completionPending = true;
          _advanceIfCompleted();
        }
      }),
      player.errors.listen((message) {
        if (_closed) return;
        error = message;
        isPlaying = false;
        _cancelPreload();
        notifyListeners();
      }),
    ]);
  }

  final AudioSession session;
  final GoogleTtsService tts;
  final AudioCacheService cache;
  final AudioPlayback player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<AudioPage> _history = [];
  int _index = -1;
  int _part = 0;
  bool _completionPending = false;
  int _preloadGeneration = 0;
  final Map<String, ({Future<File> future, CancelToken token})> _audioJobs = {};
  Future<AudioPage?>? _nextPage;
  String? _nextPageCfi;
  String? _preloadTarget;
  SharedPreferences? _preferences;
  Timer? _saveTimer;
  CancelToken? _cancelToken;
  Future<void>? _closing;
  bool _closed = false;
  bool _busy = true;
  bool _loaded = false;
  String? _activePath;
  AudioVoice voice = AudioVoice.standard;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double volume = 0.8;
  bool isPlaying = false;
  bool finished = false;
  bool fromCache = false;
  String? error;
  int cacheBytes = 0;

  AudioPage? get page => _index < 0 ? null : _history[_index];
  bool get isBusy => _busy;
  bool get isConfigured => tts.isConfigured;
  String get _resumeKey =>
      'audiorucio.resume.${cache.key(session.userId, session.bookId, '', AudioVoice.standard)}';

  Future<void> initialize() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      voice = AudioVoice.values.firstWhere(
        (item) => item.name == _preferences!.getString('audiorucio.voice'),
        orElse: () => AudioVoice.standard,
      );
      volume = (_preferences!.getDouble('audiorucio.volume') ?? 0.8).clamp(
        0,
        1,
      );
      final savedJson = _preferences!.getString(_resumeKey);
      Map<String, dynamic>? saved;
      if (savedJson != null) {
        try {
          saved = jsonDecode(savedJson) as Map<String, dynamic>;
        } catch (_) {
          saved = null;
        }
      }
      final first = await session.loadPage(session.initialCfi);
      if (_closed) return;
      if (first == null) {
        throw const AudioRucioException(
          'No hay texto para leer desde esta posición.',
        );
      }
      _history.add(first);
      _index = 0;
      if (saved?['cfi'] == first.startCfi &&
          saved?['textKey'] ==
              cache.key(session.userId, session.bookId, first.text, voice) &&
          saved?['voice'] == voice.name) {
        _part = ((saved?['part'] as num?)?.toInt() ?? 0).clamp(
          0,
          first.speechParts.length - 1,
        );
        position = Duration(
          milliseconds: (saved?['positionMs'] as num?)?.toInt() ?? 0,
        );
      }
      cacheBytes = await cache.sizeBytes();
    } catch (failure) {
      if (!_closed) error = _message(failure);
    } finally {
      if (!_closed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  String _message(Object failure) => failure is AudioRucioException
      ? failure.message
      : 'No se pudo preparar Audiorucio. Inténtalo de nuevo.';

  void _advanceIfCompleted() {
    if (_closed || _busy || !isPlaying || !_completionPending) return;
    _completionPending = false;
    unawaited(
      _run(() async {
        await _next(autoplay: true);
      }),
    );
  }

  Future<AudioPage?> _loadNextPage(String cfi) {
    if (_nextPageCfi != cfi || _nextPage == null) {
      _nextPageCfi = cfi;
      _nextPage = session.loadPage(cfi).catchError((Object failure) {
        _nextPage = null;
        throw failure;
      });
    }
    return _nextPage!;
  }

  Future<File> _generate(
    String text,
    AudioVoice selectedVoice,
    String key,
    CancelToken token,
  ) async {
    final audio = await tts.synthesize(text, selectedVoice, cancelToken: token);
    if (token.isCancelled) throw token.cancelError!;
    if (_closed) throw const AudioRucioException('El lector se ha cerrado.');
    return cache.store(key, audio, protectedPath: _activePath);
  }

  void _cancelPreload() {
    _preloadGeneration++;
    _preloadTarget = null;
    for (final job in _audioJobs.values) {
      if (job.token != _cancelToken) job.token.cancel();
    }
    _audioJobs.removeWhere((_, job) => job.token != _cancelToken);
  }

  void _preloadNext() {
    if (_closed || !isPlaying || page == null) return;
    final current = page!;
    final nextPart = _part + 1 < current.speechParts.length ? _part + 1 : 0;
    final cfi = nextPart > 0 ? current.startCfi : current.nextCfi;
    if (cfi == null) return;
    final selectedVoice = voice;
    final target = '$cfi:$nextPart:${selectedVoice.name}';
    if (_preloadTarget == target) return;
    _cancelPreload();
    _preloadTarget = target;
    final generation = _preloadGeneration;
    unawaited(() async {
      try {
        final next = nextPart > 0 ? current : await _loadNextPage(cfi);
        if (_closed || generation != _preloadGeneration || next == null) return;
        final text = next.speechParts[nextPart];
        final key = cache.key(
          session.userId,
          session.bookId,
          text,
          selectedVoice,
        );
        if (await cache.find(key) != null || !tts.isConfigured) return;
        if (_closed || generation != _preloadGeneration) return;
        final token = CancelToken();
        final future = _generate(text, selectedVoice, key, token);
        _audioJobs[key] = (future: future, token: token);
        try {
          await future;
        } finally {
          if (_audioJobs[key]?.token == token) _audioJobs.remove(key);
        }
        if (!_closed) {
          cacheBytes = await cache.sizeBytes();
          if (!_closed) notifyListeners();
        }
      } catch (_) {
        if (generation == _preloadGeneration) _preloadTarget = null;
      }
    }());
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _closed) return;
    _busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (failure) {
      if (!_closed) {
        error = _message(failure);
        isPlaying = false;
        _cancelPreload();
        try {
          await player.pause();
        } catch (_) {}
      }
    } finally {
      if (!_closed) {
        _busy = false;
        _saveSoon();
        notifyListeners();
        _advanceIfCompleted();
        if (isPlaying) _preloadNext();
      }
    }
  }

  Future<void> _activate(
    AudioPage next, {
    required bool autoplay,
    Duration offset = Duration.zero,
    double? fraction,
  }) async {
    await player.stop();
    if (_closed) return;
    _completionPending = false;
    isPlaying = false;
    _loaded = false;
    duration = Duration.zero;
    position = offset;
    final text = next.speechParts[_part];
    final key = cache.key(session.userId, session.bookId, text, voice);
    var file = await cache.find(key);
    fromCache = file != null;
    if (file == null) {
      final job = _audioJobs[key];
      _cancelToken = job?.token ?? CancelToken();
      try {
        file = job == null
            ? await _generate(text, voice, key, _cancelToken!)
            : await job.future;
      } finally {
        _cancelToken = null;
      }
    }
    if (_closed) return;
    await player.load(file.path);
    if (_closed) return;
    _activePath = file.path;
    duration = await player.getDuration() ?? duration;
    if (duration <= Duration.zero) {
      throw const AudioRucioException(
        'No se pudo obtener la duración del audio.',
      );
    }
    _loaded = true;
    position = fraction == null
        ? Duration(
            milliseconds: offset.inMilliseconds.clamp(
              0,
              duration.inMilliseconds,
            ),
          )
        : Duration(
            milliseconds: (duration.inMilliseconds * fraction.clamp(0, 1))
                .round(),
          );
    await player.setVolume(volume);
    await player.seek(position);
    if (_closed) return;
    await session.onPageChanged(next);
    await cache.trim(protectedPaths: {file.path});
    cacheBytes = await cache.sizeBytes();
    if (_closed) return;
    finished = false;
    if (autoplay) {
      isPlaying = true;
      await player.resume();
      if (_closed) return;
    }
  }

  Future<void> togglePlayback() => _run(() async {
    if (page == null) {
      final first = await session.loadPage(session.initialCfi);
      if (_closed || first == null) return;
      _history.add(first);
      _index = 0;
    }
    if (isPlaying) {
      isPlaying = false;
      _completionPending = false;
      _cancelPreload();
      await player.pause();
    } else if (!_loaded) {
      await _activate(page!, autoplay: true, offset: position);
    } else {
      if (finished) {
        position = Duration.zero;
        await player.seek(position);
        finished = false;
      }
      isPlaying = true;
      await player.resume();
    }
  });

  Future<void> changeVoice(AudioVoice nextVoice) => _run(() async {
    if (nextVoice == voice) return;
    final autoplay = isPlaying;
    final hadAudio = _loaded;
    _cancelPreload();
    _completionPending = false;
    final fraction = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    await player.pause();
    voice = nextVoice;
    _loaded = false;
    await _preferences?.setString('audiorucio.voice', voice.name);
    if (page != null && hadAudio) {
      await _activate(page!, autoplay: autoplay, fraction: fraction);
    } else {
      position = Duration.zero;
    }
  });

  Future<bool> _next({required bool autoplay}) async {
    if (_part + 1 < page!.speechParts.length) {
      _part++;
    } else if (_index + 1 < _history.length) {
      _index++;
      _part = 0;
    } else {
      final cfi = page?.nextCfi;
      if (cfi == null) {
        finished = true;
        isPlaying = false;
        position = duration;
        return false;
      }
      final next = await _loadNextPage(cfi);
      if (_closed) return false;
      if (next == null || next.startCfi == page?.startCfi) {
        finished = true;
        isPlaying = false;
        return false;
      }
      _history.add(next);
      _index++;
      _part = 0;
    }
    await _activate(page!, autoplay: autoplay);
    return true;
  }

  Future<void> skip(Duration delta) => _run(() async {
    if (!_loaded || page == null) return;
    final autoplay = isPlaying;
    _completionPending = false;
    await player.pause();
    isPlaying = false;
    var target = position + delta;
    while (target < Duration.zero && (_index > 0 || _part > 0)) {
      if (_part > 0) {
        _part--;
      } else {
        _index--;
        _part = page!.speechParts.length - 1;
      }
      await _activate(page!, autoplay: false);
      if (_closed) return;
      target += duration;
    }
    while (target >= duration && duration > Duration.zero) {
      final overflow = target - duration;
      if (!await _next(autoplay: false)) {
        target = duration;
        break;
      }
      if (_closed) return;
      target = overflow;
    }
    position = Duration(
      milliseconds: target.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
    finished = finished && position >= duration;
    await player.seek(position);
    if (autoplay && !finished && !_closed) {
      isPlaying = true;
      await player.resume();
    }
  });

  Future<void> seek(Duration target) => skip(target - position);

  Future<void> setVolume(double value) async {
    if (_closed) return;
    volume = value.clamp(0, 1);
    notifyListeners();
    try {
      await player.setVolume(volume);
      await _preferences?.setDouble('audiorucio.volume', volume);
    } catch (_) {
      if (!_closed) {
        error = 'No se pudo ajustar el volumen.';
        notifyListeners();
      }
    }
  }

  void configure(String key) {
    if (_closed) return;
    tts.apiKey = key.trim();
    error = null;
    notifyListeners();
  }

  Future<void> clearCache() => _run(() async {
    _cancelPreload();
    await player.stop();
    isPlaying = false;
    _loaded = false;
    _activePath = null;
    await cache.clear();
    cacheBytes = 0;
  });

  void _saveSoon() {
    _saveTimer ??= Timer(const Duration(seconds: 2), () {
      _saveTimer = null;
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    if (page == null) return;
    await _preferences?.setString(
      _resumeKey,
      jsonEncode({
        'cfi': page!.startCfi,
        'readerCfi': session.readerCfi?.call() ?? page!.startCfi,
        'voice': voice.name,
        'textKey': cache.key(session.userId, session.bookId, page!.text, voice),
        'part': _part,
        'positionMs': position.inMilliseconds,
      }),
    );
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    isPlaying = false;
    _cancelPreload();
    _cancelToken?.cancel();
    _saveTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await player.dispose();
    await _save();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

final audioRucioProvider = ChangeNotifierProvider.autoDispose
    .family<AudioRucioController, AudioSession>((ref, session) {
      final controller = AudioRucioController(
        session: session,
        tts: ref.read(googleTtsServiceProvider),
        cache: ref.read(audioCacheServiceProvider),
        player: ref.read(audioPlaybackFactoryProvider)(),
      );
      unawaited(controller.initialize());
      return controller;
    });
