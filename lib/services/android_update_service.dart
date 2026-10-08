import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_release.dart';

abstract class UpdateSource {
  Future<Uint8List> manifest(String userId);
  Future<String> downloadUrl(String userId, String path);
}

class SupabaseUpdateSource implements UpdateSource {
  SupabaseUpdateSource(this.client);
  final SupabaseClient client;
  static const bucket = 'rucio-updates';

  void _authorize(String userId) {
    if (client.auth.currentUser?.id != userId) {
      throw const UpdateException('Inicia sesión para buscar actualizaciones.');
    }
  }

  @override
  Future<Uint8List> manifest(String userId) {
    _authorize(userId);
    return client.storage.from(bucket).download('$userId/android/latest.json');
  }

  @override
  Future<String> downloadUrl(String userId, String path) {
    _authorize(userId);
    return client.storage.from(bucket).createSignedUrl('$userId/$path', 600);
  }
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
}

class AndroidUpdateService {
  AndroidUpdateService({
    required this.source,
    Dio? dio,
    MethodChannel? channel,
    Future<Directory> Function()? directory,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 45),
             ),
           ),
       _channel = channel ?? const MethodChannel('com.rucio/updates'),
       _directory = directory ?? getTemporaryDirectory;

  final UpdateSource source;
  final Dio _dio;
  final MethodChannel _channel;
  final Future<Directory> Function() _directory;

  Future<AndroidInstallation> installation() async =>
      AndroidInstallation.fromJson(
        Map<String, dynamic>.from(
          await _channel.invokeMethod<Map>('info') ?? {},
        ),
      );

  Future<AppRelease?> check(
    String userId,
    AndroidInstallation installed,
  ) async {
    final bytes = await source
        .manifest(userId)
        .timeout(const Duration(seconds: 20));
    if (bytes.length > 100000) throw const FormatException();
    final release = AppRelease.fromJson(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      installed,
    );
    return release.buildNumber > installed.buildNumber ? release : null;
  }

  Future<File> download(
    String userId,
    AppRelease release, {
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    final directory = Directory('${(await _directory()).path}/updates');
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/rucio-${release.buildNumber}-${release.sha256}.apk',
    );
    if (await file.exists()) {
      try {
        await verify(file, release);
        return file;
      } catch (_) {
        await file.delete();
      }
    }
    for (final old in await directory.list().toList()) {
      if (old is File && old.path != file.path) await old.delete();
    }
    final partial = File('${file.path}.part');
    try {
      final url = await source.downloadUrl(userId, release.path);
      final uri = Uri.parse(url);
      if (uri.scheme != 'https' &&
          !(uri.scheme == 'http' && uri.host == '127.0.0.1')) {
        throw const UpdateException('No se pudo obtener una descarga segura.');
      }
      await _dio.download(
        url,
        partial.path,
        cancelToken: cancelToken,
        options: Options(followRedirects: false),
        onReceiveProgress: (received, total) {
          if (received > release.bytes) cancelToken.cancel('size');
          onProgress(received, release.bytes);
        },
      );
      await verify(partial, release);
      if (cancelToken.isCancelled) {
        throw const UpdateException('Descarga cancelada.');
      }
      return await partial.rename(file.path);
    } finally {
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<void> verify(File file, AppRelease release) async {
    if (await file.length() != release.bytes ||
        (await sha256.bind(file.openRead()).first).toString() !=
            release.sha256) {
      throw const UpdateException(
        'La descarga no pasó la verificación. Vuelve a intentarlo.',
      );
    }
    await _channel.invokeMethod<void>('verify', {
      'path': file.path,
      'buildNumber': release.buildNumber,
    });
  }

  Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;
  Future<void> requestPermission() => _channel.invokeMethod<void>('permission');
  Future<void> install(File file, AppRelease release) async {
    await verify(file, release);
    await _channel.invokeMethod<void>('install', {
      'path': file.path,
      'buildNumber': release.buildNumber,
    });
  }
}
