import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rucio_flutter/services/desktop_translation_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Installs the local engine and translates with downloads disabled',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final directory = Directory('.dart_tool/translation_install_validation');
      final statuses = <String>[];
      final first = await DesktopTranslationService(directory: directory)
          .translate(
            'The book is on the table. I love reading every day.',
            onStatus: statuses.add,
          );
      expect(first, contains('libro'));
      expect(first, contains('mesa'));
      expect(first, isNot(contains('The book')));

      var downloads = 0;
      final offlineDio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              downloads++;
              handler.reject(
                DioException(requestOptions: options, error: 'Offline'),
              );
            },
          ),
        );
      final offline = await DesktopTranslationService(
        directory: directory,
        dio: offlineDio,
      ).translate('I love reading books.\n\nThe sky is blue.');
      expect(offline, contains('libros'));
      expect(offline, contains('cielo'));
      expect(offline, contains('\n\n'));
      expect(downloads, 0);
    }, _RealHttpOverrides()),
    skip:
        !Platform.isWindows ||
        Platform.environment['RUN_LOCAL_TRANSLATION_TESTS'] != 'true',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
