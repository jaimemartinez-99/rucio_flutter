import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_update_provider.dart';

class AppUpdateDialog extends ConsumerStatefulWidget {
  const AppUpdateDialog({super.key});
  @override
  ConsumerState<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends ConsumerState<AppUpdateDialog> {
  late final AppLifecycleListener _lifecycle;
  late final AppUpdateController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(appUpdateProvider.notifier);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (mounted) {
          unawaited(ref.read(appUpdateProvider.notifier).refreshPermission());
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _controller.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appUpdateProvider);
    final controller = ref.read(appUpdateProvider.notifier);
    final release = state.release;
    return AlertDialog(
      title: const Text('Actualizaciones de Rucio'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.installed != null)
                Text(
                  'Versión instalada: ${state.installed!.version} (${state.installed!.buildNumber})',
                ),
              const SizedBox(height: 16),
              if (state.phase == UpdatePhase.checking)
                const LinearProgressIndicator(),
              if (state.phase == UpdatePhase.checking)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Buscando actualizaciones…'),
                ),
              if (state.phase == UpdatePhase.current)
                const Text('Tienes la última versión disponible.'),
              if (release != null) ...[
                Text(
                  'Nueva versión: ${release.version}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(release.notes),
                const SizedBox(height: 12),
                Text('${(release.bytes / 1024 / 1024).toStringAsFixed(1)} MB'),
              ],
              if (state.phase == UpdatePhase.downloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: state.progress),
                const SizedBox(height: 8),
                Text('Descargando… ${(state.progress * 100).round()}%'),
              ],
              if (state.phase == UpdatePhase.ready) ...[
                const SizedBox(height: 16),
                Text(
                  state.canInstall
                      ? 'Descarga verificada. Android te pedirá confirmar la actualización. Tus datos se conservarán.'
                      : 'Para actualizar, permite que Rucio instale aplicaciones en la siguiente pantalla. Después vuelve aquí y pulsa Instalar actualización.',
                ),
              ],
              if (state.error != null) ...[
                const SizedBox(height: 16),
                Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            controller.cancel();
            Navigator.pop(context);
          },
          child: Text(state.busy ? 'Cancelar' : 'Cerrar'),
        ),
        if (!state.busy && release == null)
          FilledButton(
            onPressed: () => controller.check(),
            child: const Text('Buscar actualizaciones'),
          ),
        if (state.phase == UpdatePhase.available)
          FilledButton(
            onPressed: controller.download,
            child: const Text('Descargar actualización'),
          ),
        if (state.phase == UpdatePhase.ready)
          FilledButton(
            onPressed: controller.install,
            child: Text(
              state.canInstall
                  ? 'Instalar actualización'
                  : 'Permitir instalación',
            ),
          ),
      ],
    );
  }
}
