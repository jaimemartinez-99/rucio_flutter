import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rucio_flutter/models/app_release.dart';
import 'package:rucio_flutter/providers/app_update_provider.dart';
import 'package:rucio_flutter/services/android_update_service.dart';
import 'package:rucio_flutter/widgets/app_update_dialog.dart';

class UnusedSource implements UpdateSource {
  @override
  Future<Uint8List> manifest(String userId) => throw UnimplementedError();
  @override
  Future<String> downloadUrl(String userId, String path) =>
      throw UnimplementedError();
}

class DialogController extends AppUpdateController {
  DialogController()
    : super(AndroidUpdateService(source: UnusedSource()), 'user') {
    state = AppUpdateState(
      phase: UpdatePhase.ready,
      release: AppRelease(
        version: '1.0.1',
        buildNumber: 2,
        notes: List.filled(15, 'Novedades de Rucio.').join('\n'),
        path: 'android/2/rucio-arm64-v8a.apk',
        bytes: 40000000,
        sha256: 'a' * 64,
      ),
    );
  }
  bool cancelled = false;
  bool permissionRequested = false;
  bool installed = false;

  @override
  void cancel() {
    cancelled = true;
    super.cancel();
  }

  @override
  Future<void> install() async {
    if (!state.canInstall) {
      permissionRequested = true;
      state = AppUpdateState(
        phase: UpdatePhase.ready,
        release: state.release,
        canInstall: true,
      );
    } else {
      installed = true;
    }
  }
}

void main() {
  testWidgets('fits a phone and offers permission before installation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = DialogController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appUpdateProvider.overrideWith((ref) => controller)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AppUpdateDialog(),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Permitir instalación'));
    await tester.pumpAndSettle();
    expect(controller.permissionRequested, isTrue);
    await tester.tap(find.text('Instalar actualización'));
    await tester.pumpAndSettle();
    expect(controller.installed, isTrue);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(controller.cancelled, isTrue);
    expect(find.byType(AppUpdateDialog), findsNothing);
  });
}
