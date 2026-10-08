import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_page.dart';
import 'audio_usage_service.dart';

class AudioRucioException implements Exception {
  const AudioRucioException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GoogleTtsService {
  GoogleTtsService({Dio? dio, AudioUsageService? usage})
    : _dio = dio ?? Dio(),
      _usage = usage ?? AudioUsageService();

  final Dio _dio;
  final AudioUsageService _usage;
  String apiKey = const String.fromEnvironment('GOOGLE_CLOUD_TTS_API_KEY');

  bool get isConfigured => apiKey.trim().isNotEmpty;

  Future<Uint8List> synthesize(
    String text,
    AudioVoice voice, {
    CancelToken? cancelToken,
  }) async {
    if (!isConfigured) {
      throw const AudioRucioException(
        'Conecta Google Cloud para iniciar la voz.',
      );
    }
    if (text.trim().isEmpty || utf8.encode(text).length > 5000) {
      throw const AudioRucioException('El fragmento de lectura no es válido.');
    }
    if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
    final AudioUsageRequest request;
    try {
      request = await _usage.begin(text, voice);
    } catch (_) {
      throw const AudioRucioException(
        'No se pudo registrar el consumo. Revisa el almacenamiento local e inténtalo de nuevo.',
      );
    }
    try {
      if (cancelToken?.isCancelled ?? false) {
        await _usage.finish(request, generated: false);
        throw cancelToken!.cancelError!;
      }
      final response = await _dio.post<Map<String, dynamic>>(
        'https://texttospeech.googleapis.com/v1/text:synthesize',
        options: Options(
          headers: {'X-Goog-Api-Key': apiKey.trim()},
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 60),
        ),
        cancelToken: cancelToken,
        data: {
          'input': {'text': text},
          'voice': {'languageCode': 'es-ES', 'name': voice.apiName},
          'audioConfig': {'audioEncoding': 'MP3'},
        },
      );
      await _usage.finish(request, generated: true);
      final content = response.data?['audioContent'];
      if (content is! String || content.isEmpty) {
        throw const AudioRucioException('Google Cloud no devolvió audio.');
      }
      final bytes = base64Decode(content);
      if (bytes.isEmpty) {
        throw const AudioRucioException('Google Cloud devolvió audio vacío.');
      }
      return bytes;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status != null && status >= 400 && status < 500) {
        await _usage.finish(request, generated: false);
      }
      if (CancelToken.isCancel(error)) rethrow;
      final message = switch (error.response?.statusCode) {
        400 => 'Revisa la clave de Google Cloud y la disponibilidad de la voz.',
        401 || 403 =>
          'Google Cloud rechazó el acceso. Revisa la clave, la API y la facturación.',
        429 => 'Se ha alcanzado la cuota de Google Cloud. Inténtalo más tarde.',
        _ =>
          'No se pudo generar la voz. Comprueba tu conexión e inténtalo de nuevo.',
      };
      throw AudioRucioException(message);
    } on FormatException {
      throw const AudioRucioException('Google Cloud devolvió audio no válido.');
    }
  }
}

final googleTtsServiceProvider = Provider<GoogleTtsService>((ref) {
  return GoogleTtsService(usage: ref.read(audioUsageServiceProvider));
});
