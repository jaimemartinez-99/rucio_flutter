import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/audio_page.dart';

extension AudioVoicePricing on AudioVoice {
  int get freeCharacters => switch (this) {
    AudioVoice.standard => 4000000,
    AudioVoice.premium => 1000000,
  };

  double get usdPerMillion => switch (this) {
    AudioVoice.standard => 4,
    AudioVoice.premium => 30,
  };
}

class AudioUsageTotals {
  const AudioUsageTotals({this.characters = 0, this.unconfirmedCharacters = 0});

  final int characters;
  final int unconfirmedCharacters;

  double estimatedUsd(AudioVoice voice) =>
      (characters - voice.freeCharacters).clamp(0, characters) *
      voice.usdPerMillion /
      1000000;

  double listPriceUsd(AudioVoice voice) =>
      characters * voice.usdPerMillion / 1000000;

  Map<String, dynamic> toJson() => {
    'characters': characters,
    'unconfirmedCharacters': unconfirmedCharacters,
  };

  factory AudioUsageTotals.fromJson(Map<String, dynamic> json) {
    final characters = json['characters'];
    final unconfirmed = json['unconfirmedCharacters'];
    if (characters is! int ||
        characters < 0 ||
        unconfirmed is! int ||
        unconfirmed < 0) {
      throw const FormatException('Invalid audio usage');
    }
    return AudioUsageTotals(
      characters: characters,
      unconfirmedCharacters: unconfirmed,
    );
  }
}

class AudioUsageRequest {
  const AudioUsageRequest(this.month, this.voice, this.characters);

  final String month;
  final AudioVoice voice;
  final int characters;
}

class AudioUsageService extends ChangeNotifier {
  AudioUsageService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const preferencesKey = 'audiorucio.usage.v1';
  final DateTime Function() _now;
  final Map<String, Map<AudioVoice, AudioUsageTotals>> _months = {};
  Future<void> _queue = Future.value();
  SharedPreferences? _preferences;
  DateTime? trackedSince;
  String? error;
  bool _disposed = false;

  String get currentMonth => monthKey(_now());
  bool get isLoaded => _preferences != null;
  List<String> get months =>
      ({currentMonth, ..._months.keys}.toList()
        ..sort((a, b) => b.compareTo(a)));

  static String monthKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  AudioUsageTotals totals(String month, AudioVoice voice) =>
      _months[month]?[voice] ?? const AudioUsageTotals();

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    if (_preferences != null) return;
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(preferencesKey);
    final loaded = <String, Map<AudioVoice, AudioUsageTotals>>{};
    DateTime? since;
    if (stored != null) {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      since = DateTime.parse(json['trackedSince'] as String);
      final months = json['months'] as Map<String, dynamic>;
      for (final entry in months.entries) {
        final voices = entry.value as Map<String, dynamic>;
        loaded[entry.key] = {
          for (final voice in AudioVoice.values)
            if (voices[voice.name] != null)
              voice: AudioUsageTotals.fromJson(
                voices[voice.name] as Map<String, dynamic>,
              ),
        };
      }
    }
    trackedSince = since ?? _now();
    _months.addAll(loaded);
    _preferences = preferences;
  }

  Future<void> initialize() => _enqueue(() async {
    try {
      await _load();
      error = null;
    } catch (_) {
      error = 'No se pudo leer el registro local de consumo.';
    }
    _notify();
  });

  Future<void> _write(
    String month,
    AudioVoice voice,
    AudioUsageTotals totals,
  ) async {
    final updated = {
      ..._months,
      month: {...?_months[month], voice: totals},
    };
    final saved = await _preferences!.setString(
      preferencesKey,
      jsonEncode({
        'trackedSince': trackedSince!.toIso8601String(),
        'months': {
          for (final month in updated.entries)
            month.key: {
              for (final voice in month.value.entries)
                voice.key.name: voice.value.toJson(),
            },
        },
      }),
    );
    if (!saved) throw StateError('Audio usage could not be saved');
    _months[month] = updated[month]!;
    error = null;
    _notify();
  }

  Future<AudioUsageRequest> begin(String text, AudioVoice voice) {
    final request = AudioUsageRequest(currentMonth, voice, text.runes.length);
    return _enqueue(() async {
      try {
        await _load();
        final previous = totals(request.month, voice);
        await _write(
          request.month,
          voice,
          AudioUsageTotals(
            characters: previous.characters,
            unconfirmedCharacters:
                previous.unconfirmedCharacters + request.characters,
          ),
        );
        return request;
      } catch (_) {
        error = 'No se pudo guardar el registro local de consumo.';
        _notify();
        rethrow;
      }
    });
  }

  Future<void> finish(AudioUsageRequest request, {required bool generated}) =>
      _enqueue(() async {
        try {
          final previous = totals(request.month, request.voice);
          await _write(
            request.month,
            request.voice,
            AudioUsageTotals(
              characters:
                  previous.characters + (generated ? request.characters : 0),
              unconfirmedCharacters:
                  previous.unconfirmedCharacters - request.characters,
            ),
          );
        } catch (_) {
          error =
              'El último consumo no se pudo confirmar en el registro local.';
          _notify();
        }
      });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final audioUsageServiceProvider = ChangeNotifierProvider<AudioUsageService>(
  (ref) => AudioUsageService(),
);
