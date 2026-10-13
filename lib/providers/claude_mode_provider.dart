import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/claude_mode.dart';

class ClaudeModeNotifier extends StateNotifier<ClaudeReadingMode> {
  ClaudeModeNotifier() : super(ClaudeReadingMode.economical) {
    initialized = _load();
  }

  static const preferencesKey = 'claude.reading.mode';
  late final Future<void> initialized;
  int _revision = 0;
  Future<void> _writes = Future.value();

  Future<void> _load() async {
    try {
      final revision = _revision;
      final preferences = await SharedPreferences.getInstance();
      final name = preferences.getString(preferencesKey);
      if (!mounted || revision != _revision) return;
      state = ClaudeReadingMode.values.firstWhere(
        (mode) => mode.name == name,
        orElse: () => ClaudeReadingMode.economical,
      );
    } catch (_) {}
  }

  Future<void> select(ClaudeReadingMode mode) {
    _revision++;
    state = mode;
    final write = _writes.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(preferencesKey, mode.name)) {
        throw StateError('No se pudo guardar el modo de Claude.');
      }
    });
    _writes = write.catchError((Object _) {});
    return write;
  }
}

final claudeModeProvider =
    StateNotifierProvider<ClaudeModeNotifier, ClaudeReadingMode>(
      (ref) => ClaudeModeNotifier(),
    );
