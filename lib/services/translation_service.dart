import 'dart:io' show Platform;

import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'desktop_translation_service.dart';

class TranslationServiceException implements Exception {
  const TranslationServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TranslationService {
  Future<String> translateEnglishToSpanish(
    String text, {
    void Function(String)? onStatus,
  }) async {
    final selection = text.trim();
    if (selection.isEmpty) {
      throw const TranslationServiceException(
        'Selecciona texto para traducir.',
      );
    }
    if (Platform.isWindows) {
      try {
        return await DesktopTranslationService().translate(
          selection,
          onStatus: onStatus,
        );
      } catch (error) {
        throw TranslationServiceException('La traducción local falló: $error');
      }
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw const TranslationServiceException(
        'El motor local no está disponible en este sistema.',
      );
    }
    onStatus?.call(
      'Preparando la traducción local. La primera vez se descargarán los modelos.',
    );

    final modelManager = OnDeviceTranslatorModelManager();
    final sourceLanguage = TranslateLanguage.english;
    final targetLanguage = TranslateLanguage.spanish;
    final translator = OnDeviceTranslator(
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );

    try {
      final sourceReady = await modelManager.downloadModel(
        sourceLanguage.bcpCode,
      );
      final targetReady = await modelManager.downloadModel(
        targetLanguage.bcpCode,
      );
      if (!sourceReady || !targetReady) {
        throw const TranslationServiceException(
          'No se pudieron descargar los modelos de inglés y español.',
        );
      }
      final translation = (await translator.translateText(selection)).trim();
      if (translation.isEmpty) {
        throw const TranslationServiceException('La traducción está vacía.');
      }
      return translation;
    } catch (error) {
      if (error is TranslationServiceException) rethrow;
      throw TranslationServiceException('La traducción falló: $error');
    } finally {
      await translator.close();
    }
  }
}
