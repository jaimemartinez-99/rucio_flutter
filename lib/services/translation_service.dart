import 'dart:io' show Platform;

import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslationServiceException implements Exception {
  const TranslationServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TranslationService {
  Future<String> translateEnglishToSpanish(String text) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw const TranslationServiceException(
        'La traducción sin conexión solo está disponible en Android e iOS.',
      );
    }
    final selection = text.trim();
    if (selection.isEmpty) {
      throw const TranslationServiceException('Selecciona texto para traducir.');
    }

    final modelManager = OnDeviceTranslatorModelManager();
    final sourceLanguage = TranslateLanguage.english;
    final targetLanguage = TranslateLanguage.spanish;
    final translator = OnDeviceTranslator(
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );

    try {
      final sourceReady = await modelManager.downloadModel(sourceLanguage.bcpCode);
      final targetReady = await modelManager.downloadModel(targetLanguage.bcpCode);
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
