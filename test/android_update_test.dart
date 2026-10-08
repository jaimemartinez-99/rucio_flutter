import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rucio_flutter/models/app_release.dart';
import 'package:rucio_flutter/providers/app_update_provider.dart';
import 'package:rucio_flutter/services/android_update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryUpdateSource implements UpdateSource {
  MemoryUpdateSource(this.data);
  Map<String, dynamic> data;
  String url = '';
  int downloads = 0;
  int checks = 0;
  bool offline = false;

  @override
  Future<Uint8List> manifest(String userId) async {
    checks++;
    if (offline) throw const SocketException('offline');
    return Uint8List.fromList(utf8.encode(jsonEncode(data)));
  }

  @override
  Future<String> downloadUrl(String userId, String path) async {
    downloads++;
    return url;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.rucio/updates');
  final certificate = 'a' * 64;
  final payload = utf8.encode('verified APK test payload');
  late AndroidInstallation installed;
  late Map<String, dynamic> data;
  late MemoryUpdateSource source;
  late AndroidUpdateService service;
  late Directory temporary;
  late HttpServer server;
  late List<String> calls;
  late List<int> response;
  var nativeRejects = false;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    installed = AndroidInstallation(
      packageId: 'com.rucio.rucio_flutter',
      version: '1.0.0',
      buildNumber: 1,
      abis: const ['arm64-v8a', 'armeabi-v7a'],
      certificates: [certificate],
    );
    data = {
      'schema': 1,
      'packageId': installed.packageId,
      'version': '1.0.1',
      'buildNumber': 2,
      'notes': 'Actualización',
      'certificateSha256': certificate,
      'artifacts': {
        'arm64-v8a': {
          'path': 'android/2/rucio-arm64-v8a.apk',
          'bytes': payload.length,
          'sha256': sha256.convert(payload).toString(),
        },
      },
    };
    response = payload;
    calls = [];
    nativeRejects = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'info') {
            return {
              'packageId': installed.packageId,
              'version': installed.version,
              'buildNumber': installed.buildNumber,
              'abis': installed.abis,
              'certificates': installed.certificates,
            };
          }
          if (call.method == 'verify' && nativeRejects) {
            throw PlatformException(code: 'invalid_update');
          }
          if (call.method == 'canInstall') return true;
          return null;
        });
    temporary = await Directory.systemTemp.createTemp('rucio_updates_test_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.add(response);
      await request.response.close();
    });
    source = MemoryUpdateSource(data)
      ..url = 'http://127.0.0.1:${server.port}/release.apk';
    service = AndroidUpdateService(
      source: source,
      dio: Dio()
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () => HttpClient()..findProxy = (_) => 'DIRECT',
        ),
      channel: channel,
      directory: () async => temporary,
    );
  });

  tearDown(() async {
    await server.close(force: true);
    await temporary.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('selects the device ABI and rejects incompatible metadata', () {
    expect(
      AppRelease.fromJson(data, installed).path,
      'android/2/rucio-arm64-v8a.apk',
    );
    for (final change in [
      {'packageId': 'another.app'},
      {'certificateSha256': 'b' * 64},
      {'buildNumber': -1},
      {'schema': 2},
      {'artifacts': {}},
    ]) {
      expect(
        () => AppRelease.fromJson({...data, ...change}, installed),
        throwsFormatException,
      );
    }
    final artifact = (data['artifacts'] as Map)['arm64-v8a'] as Map;
    for (final change in [
      {'path': '../outside.apk'},
      {'bytes': 51 * 1024 * 1024},
      {'sha256': 'invalid'},
    ]) {
      expect(
        () => AppRelease.fromJson({
          ...data,
          'artifacts': {
            'arm64-v8a': {...artifact, ...change},
          },
        }, installed),
        throwsFormatException,
      );
    }
  });

  test(
    'downloads atomically, verifies natively and reuses valid cache',
    () async {
      final release = (await service.check('user', installed))!;
      Future<File> download() => service.download(
        'user',
        release,
        cancelToken: CancelToken(),
        onProgress: (_, _) {},
      );
      final file = await download();
      expect(await file.readAsBytes(), payload);
      expect(await download(), isA<File>());
      expect(source.downloads, 1);
      expect(calls.where((call) => call == 'verify').length, 2);
      expect(
        await temporary
            .list(recursive: true)
            .where((entry) => entry.path.endsWith('.part'))
            .isEmpty,
        isTrue,
      );
    },
  );

  test(
    'rejects corrupted or oversized downloads and removes partial files',
    () async {
      final release = AppRelease.fromJson(data, installed);
      for (final invalid in [
        List.filled(payload.length, 0),
        [...payload, 0],
      ]) {
        response = invalid;
        await expectLater(
          service.download(
            'user',
            release,
            cancelToken: CancelToken(),
            onProgress: (_, _) {},
          ),
          throwsA(anything),
        );
        expect(
          await Directory('${temporary.path}/updates').list().isEmpty,
          isTrue,
        );
      }
      expect(calls.contains('verify'), isFalse);
    },
  );

  test('native rejection blocks APK use', () async {
    nativeRejects = true;
    await expectLater(
      service.download(
        'user',
        AppRelease.fromJson(data, installed),
        cancelToken: CancelToken(),
        onProgress: (_, _) {},
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(await Directory('${temporary.path}/updates').list().isEmpty, isTrue);
  });

  test('rechecks file integrity immediately before installation', () async {
    final release = AppRelease.fromJson(data, installed);
    final file = await service.download(
      'user',
      release,
      cancelToken: CancelToken(),
      onProgress: (_, _) {},
    );
    await file.writeAsBytes(List.filled(payload.length, 0));
    await expectLater(
      service.install(file, release),
      throwsA(isA<UpdateException>()),
    );
    expect(calls.contains('install'), isFalse);
  });

  test(
    'failed automatic checks remain retryable and manual checks bypass throttle',
    () async {
      final controller = AppUpdateController(service, 'user');
      addTearDown(controller.dispose);
      source.offline = true;
      expect(await controller.check(automatic: true), isFalse);
      source.offline = false;
      expect(await controller.check(automatic: true), isTrue);
      expect(await controller.check(automatic: true), isFalse);
      expect(source.checks, 2);
      expect(await controller.check(), isTrue);
      expect(source.checks, 3);
      await controller.download();
      expect(controller.state.phase, UpdatePhase.ready);
      await controller.install();
      expect(calls.last, 'install');
    },
  );

  test('installed releases do not prompt an update', () async {
    data['buildNumber'] = 1;
    (data['artifacts'] as Map)['arm64-v8a']['path'] =
        'android/1/rucio-arm64-v8a.apk';
    expect(await service.check('user', installed), isNull);
  });
}
