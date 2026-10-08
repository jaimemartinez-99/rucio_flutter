import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_release.dart';
import '../services/android_update_service.dart';
import 'auth_provider.dart';

enum UpdatePhase { idle, checking, current, available, downloading, ready }

class AppUpdateState {
  const AppUpdateState({
    this.phase = UpdatePhase.idle,
    this.installed,
    this.release,
    this.progress = 0,
    this.error,
    this.canInstall = false,
  });

  final UpdatePhase phase;
  final AndroidInstallation? installed;
  final AppRelease? release;
  final double progress;
  final String? error;
  final bool canInstall;
  bool get busy =>
      phase == UpdatePhase.checking || phase == UpdatePhase.downloading;
}

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(this.service, this.userId)
    : super(const AppUpdateState());
  final AndroidUpdateService service;
  final String? userId;
  CancelToken? _cancel;
  File? _apk;

  String _message(Object error) {
    if (error is UpdateException) return error.message;
    if (error is FormatException) {
      return error.message.isNotEmpty
          ? error.message
          : 'La información de la actualización no es válida.';
    }
    if (error is PlatformException) {
      return error.message ?? 'No se pudo abrir el instalador.';
    }
    return 'No se pudo comprobar o descargar la actualización. Comprueba la conexión e inténtalo de nuevo.';
  }

  Future<bool> check({bool automatic = false}) async {
    if (state.busy || userId == null) return false;
    if (automatic) {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt('updates.lastCheck.$userId') ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - last <
          const Duration(hours: 12).inMilliseconds) {
        return false;
      }
    }
    if (!mounted || state.busy) return false;
    state = AppUpdateState(
      phase: UpdatePhase.checking,
      installed: state.installed,
    );
    try {
      final installed = await service.installation();
      final release = await service.check(userId!, installed);
      if (!mounted) return false;
      state = AppUpdateState(
        phase: release == null ? UpdatePhase.current : UpdatePhase.available,
        installed: installed,
        release: release,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'updates.lastCheck.$userId',
        DateTime.now().millisecondsSinceEpoch,
      );
      return release != null;
    } catch (error) {
      if (mounted) {
        state = AppUpdateState(
          installed: state.installed,
          error: _message(error),
        );
      }
      return false;
    }
  }

  Future<void> download() async {
    final release = state.release;
    if (release == null || state.busy || userId == null) return;
    final installed = state.installed;
    final token = CancelToken();
    _cancel = token;
    state = AppUpdateState(
      phase: UpdatePhase.downloading,
      installed: installed,
      release: release,
    );
    try {
      final apk = await service.download(
        userId!,
        release,
        cancelToken: token,
        onProgress: (received, total) {
          if (mounted && !token.isCancelled) {
            state = AppUpdateState(
              phase: UpdatePhase.downloading,
              installed: installed,
              release: release,
              progress: (received / total).clamp(0, 1),
            );
          }
        },
      );
      if (!mounted || token.isCancelled) return;
      _apk = apk;
      final permitted = await service.canInstall();
      if (mounted) {
        state = AppUpdateState(
          phase: UpdatePhase.ready,
          installed: installed,
          release: release,
          canInstall: permitted,
        );
      }
    } catch (error) {
      if (mounted) {
        state = AppUpdateState(
          phase: UpdatePhase.available,
          installed: installed,
          release: release,
          error: token.isCancelled ? null : _message(error),
        );
      }
    } finally {
      if (_cancel == token) _cancel = null;
    }
  }

  void cancel() {
    _cancel?.cancel();
  }

  Future<void> refreshPermission() async {
    if (state.phase != UpdatePhase.ready) return;
    try {
      final permitted = await service.canInstall();
      if (mounted) {
        state = AppUpdateState(
          phase: state.phase,
          installed: state.installed,
          release: state.release,
          canInstall: permitted,
        );
      }
    } catch (_) {}
  }

  Future<void> install() async {
    if (_apk == null ||
        state.release == null ||
        state.phase != UpdatePhase.ready) {
      return;
    }
    try {
      if (!await service.canInstall()) {
        await service.requestPermission();
        return;
      }
      await service.install(_apk!, state.release!);
    } catch (error) {
      if (mounted) {
        state = AppUpdateState(
          phase: state.phase,
          installed: state.installed,
          release: state.release,
          canInstall: state.canInstall,
          error: _message(error),
        );
      }
    }
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}

final androidUpdateServiceProvider = Provider<AndroidUpdateService>(
  (ref) => AndroidUpdateService(
    source: SupabaseUpdateSource(Supabase.instance.client),
  ),
);

final appUpdateProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>((ref) {
      final userId = ref.watch(authProvider.select((state) => state.user?.id));
      return AppUpdateController(
        ref.read(androidUpdateServiceProvider),
        userId,
      );
    });
