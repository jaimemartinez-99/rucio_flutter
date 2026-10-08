import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class DesktopTranslationService {
  DesktopTranslationService({Directory? directory, Dio? dio})
    : _directory = directory,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(minutes: 10),
              headers: {'User-Agent': 'Mozilla/5.0 Rucio/1.0'},
            ),
          );

  static final _installations = <String, Future<String>>{};
  static const _uvVersion = '0.12.23';
  static const _uvHash =
      '75d05de6762778c31ee183398de7dd15093fad0ed90b1f236d8205ea5ec00c90';
  static const _modelHash =
      'd698d0ef87ad70d5d184b7fa6965905bf4368f09a2bb9ffb165a79bac96af0c4';
  final Directory? _directory;
  final Dio _dio;

  Future<String> translate(
    String text, {
    void Function(String)? onStatus,
  }) async {
    final base =
        _directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/translation',
        );
    final root = base.absolute.path;
    final install = _installations.putIfAbsent(
      root,
      () => _prepare(root, onStatus),
    );
    String python;
    try {
      python = await install;
    } finally {
      if (identical(_installations[root], install)) {
        _installations.remove(root);
      }
    }
    onStatus?.call('Traduciendo en este dispositivo...');
    final process = await Process.start(
      python,
      ['$root/translate.py', '$root/models/en_es'],
      environment: {'PYTHONIOENCODING': 'utf-8'},
    );
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    process.stdin.encoding = utf8;
    process.stdin.write(jsonEncode({'text': text}));
    await process.stdin.close();
    try {
      final results = await Future.wait<Object>([
        process.exitCode,
        output,
        errors,
      ]).timeout(const Duration(minutes: 2));
      if (results[0] != 0) {
        throw StateError(
          'El motor local no pudo traducir. Inténtalo de nuevo.',
        );
      }
      final data = jsonDecode(results[1] as String) as Map<String, dynamic>;
      final translation = (data['translation'] as String?)?.trim();
      if (translation == null || translation.isEmpty) {
        throw StateError('La traducción está vacía.');
      }
      return translation;
    } on TimeoutException {
      process.kill();
      throw StateError(
        'La traducción local tardó demasiado. Prueba con un fragmento más corto.',
      );
    }
  }

  Future<String> _prepare(String root, void Function(String)? onStatus) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('El motor de escritorio requiere Windows.');
    }
    await Directory(root).create(recursive: true);
    final worker = await rootBundle.loadString(
      'assets/translation/translate.py',
    );
    await File('$root/translate.py').writeAsString(worker);
    final python = '$root/runtime/Scripts/python.exe';
    final marker = File('$root/installed-v1');
    if (await marker.exists() &&
        await File(python).exists() &&
        await File('$root/models/en_es/model/model.bin').exists() &&
        await File('$root/models/en_es/sentencepiece.model').exists()) {
      return python;
    }

    onStatus?.call(
      'Descargando el motor local. Solo es necesario la primera vez...',
    );
    final uvZip = File('$root/uv.zip');
    await _download(
      'https://github.com/astral-sh/uv/releases/download/$_uvVersion/uv-x86_64-pc-windows-msvc.zip',
      uvZip,
      _uvHash,
    );
    await _extract(uvZip.path, '$root/tools');
    final uv = '$root/tools/uv.exe';
    final environment = {
      'UV_PYTHON_INSTALL_DIR': '$root/python',
      'UV_CACHE_DIR': '$root/cache',
      'UV_NO_PROGRESS': '1',
    };
    onStatus?.call(
      'Preparando el motor local. La primera descarga puede tardar unos minutos...',
    );
    await _run(uv, [
      'venv',
      '--python',
      '3.11',
      '--managed-python',
      '--no-project',
      '--allow-existing',
      '$root/runtime',
    ], environment);
    await _run(uv, [
      'pip',
      'install',
      '--python',
      python,
      'ctranslate2==4.8.2',
      'sentencepiece==0.2.1',
      'numpy==2.4.6',
      'pyyaml==6.0.3',
    ], environment);
    onStatus?.call('Descargando el modelo inglés → español (88 MB)...');
    final model = File('$root/model.argosmodel');
    await _download(
      'https://argos-net.com/v1/translate-en_es-1_0.argosmodel',
      model,
      _modelHash,
    );
    await _extract(model.path, '$root/models');
    await marker.writeAsString('ctranslate2-4.8.2-en_es-1.0');
    return python;
  }

  Future<void> _download(String url, File target, String hash) async {
    if (await target.exists() && await _hash(target) == hash) return;
    final partial = File('${target.path}.part');
    try {
      await _dio.download(url, partial.path);
      if (await _hash(partial) != hash) {
        throw StateError(
          'La descarga del motor local está dañada. Vuelve a intentarlo.',
        );
      }
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
    } finally {
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<String> _hash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<void> _extract(String archivePath, String destination) {
    return Isolate.run(() {
      final input = InputFileStream(archivePath);
      try {
        final archive = ZipDecoder().decodeStream(input);
        extractArchiveToDiskSync(archive, destination);
      } finally {
        input.closeSync();
      }
    });
  }

  Future<void> _run(
    String executable,
    List<String> arguments,
    Map<String, String> environment,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      environment: environment,
    );
    final output = process.stdout.drain<void>();
    final errors = process.stderr.drain<void>();
    try {
      final result = await process.exitCode.timeout(
        const Duration(minutes: 10),
      );
      await Future.wait([output, errors]);
      if (result != 0) {
        throw StateError(
          'No se pudo preparar el motor local. Comprueba la conexión y vuelve a intentarlo.',
        );
      }
    } on TimeoutException {
      process.kill();
      throw StateError(
        'La instalación del motor local tardó demasiado. Vuelve a intentarlo.',
      );
    }
  }
}
