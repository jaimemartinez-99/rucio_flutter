import 'dart:async';
import 'dart:convert';

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
        if (!_closed && !_busy && isPlaying) {
          unawaited(_run(() => _next(autoplay: true)));
        }
      }),
      player.errors.listen((message) {
        if (_closed) return;
        error = message;
        isPlaying = false;
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
      final resumeCfi = saved?['readerCfi'] == session.initialCfi
          ? (saved?['cfi'] as String?) ?? session.initialCfi
          : session.initialCfi;
      final first = await session.loadPage(resumeCfi);
      if (_closed) return;
      if (first == null) {
        throw const AudioRucioException(
          'No hay texto para leer desde esta posición.',
        );
      }
      _history.add(first);
      _index = 0;
      if (saved?['cfi'] == first.startCfi && saved?['voice'] == voice.name) {
        position = Duration(
          milliseconds: (saved?['positionMs'] as num?)?.toInt() ?? 0,
        );
      }
      cacheBytes = await cache.sizeBytes();
      final cached = await cache.find(
        cache.key(session.userId, session.bookId, first.text, voice),
      );
      if (_closed) return;
      if (tts.isConfigured || cached != null) {
        await _activate(first, autoplay: true, offset: position);
      }
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
        try {
          await player.pause();
        } catch (_) {}
      }
    } finally {
      if (!_closed) {
        _busy = false;
        _saveSoon();
        notifyListeners();
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
    isPlaying = false;
    _loaded = false;
    duration = Duration.zero;
    position = offset;
    final key = cache.key(session.userId, session.bookId, next.text, voice);
    var file = await cache.find(key);
    fromCache = file != null;
    if (file == null) {
      _cancelToken = CancelToken();
      final audio = await tts.synthesize(
        next.text,
        voice,
        cancelToken: _cancelToken,
      );
      if (_closed) return;
      file = await cache.store(key, audio, protectedPath: _activePath);
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
      await player.resume();
      if (_closed) return;
      isPlaying = true;
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
      await player.pause();
      isPlaying = false;
    } else if (!_loaded) {
      await _activate(page!, autoplay: true, offset: position);
    } else {
      if (finished) {
        position = Duration.zero;
        await player.seek(position);
        finished = false;
      }
      await player.resume();
      isPlaying = true;
    }
  });

  Future<void> changeVoice(AudioVoice nextVoice) => _run(() async {
    if (nextVoice == voice) return;
    final autoplay = isPlaying;
    final fraction = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    await player.pause();
    voice = nextVoice;
    _loaded = false;
    await _preferences?.setString('audiorucio.voice', voice.name);
    if (page != null && (tts.isConfigured || _activePath != null)) {
      await _activate(page!, autoplay: autoplay, fraction: fraction);
    }
  });

  Future<bool> _next({required bool autoplay}) async {
    if (_index + 1 < _history.length) {
      _index++;
    } else {
      final cfi = page?.nextCfi;
      if (cfi == null) {
        finished = true;
        isPlaying = false;
        position = duration;
        return false;
      }
      final next = await session.loadPage(cfi);
      if (_closed) return false;
      if (next == null || next.startCfi == page?.startCfi) {
        finished = true;
        isPlaying = false;
        return false;
      }
      _history.add(next);
      _index++;
    }
    await _activate(page!, autoplay: autoplay);
    return true;
  }

  Future<void> skip(Duration delta) => _run(() async {
    if (!_loaded || page == null) return;
    final autoplay = isPlaying;
    await player.pause();
    isPlaying = false;
    var target = position + delta;
    while (target < Duration.zero && _index > 0) {
      _index--;
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
      await player.resume();
      isPlaying = true;
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
        'positionMs': position.inMilliseconds,
      }),
    );
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
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
