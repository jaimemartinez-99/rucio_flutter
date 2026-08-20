import 'package:dio/dio.dart';

class ClaudeServiceException implements Exception {
  const ClaudeServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ClaudeService {
  static const _apiUrl = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-sonnet-5';
  static const _apiKey = String.fromEnvironment('CLAUDE_API_KEY');

  final Dio _dio;

  ClaudeService()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

  Future<String> ask(
    String question,
    String? selectedText, {
    String? readingContext,
  }) async {
    final apiKey = _apiKey.trim();
    if (apiKey.isEmpty || apiKey.startsWith('<')) {
      throw const ClaudeServiceException(
        'Claude API key is missing from .env.',
      );
    }

    final location = readingContext == null || readingContext.trim().isEmpty
        ? ''
        : 'The reader is currently at ${readingContext.trim()}. '
              'Avoid spoilers: discuss only information available up to this point. '
              'Do not reveal later plot events, character developments, identities, or twists. '
              'If answering would require later information, say so without revealing it.\n\n';
    final passage = selectedText == null || selectedText.trim().isEmpty
        ? ''
        : 'Selected passage:\n"${selectedText.trim()}"\n\n';
    final prompt = '$location${passage}Question: ${question.trim()}';

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _apiUrl,
        options: Options(
          contentType: Headers.jsonContentType,
          headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
        ),
        data: {
          'model': _model,
          'max_tokens': 1024,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        },
      );

      final content = response.data?['content'];
      if (content is! List) {
        throw const ClaudeServiceException(
          'Claude returned an unexpected response.',
        );
      }

      final answer = content
          .whereType<Map>()
          .where((item) => item['type'] == 'text')
          .map((item) => item['text']?.toString() ?? '')
          .join()
          .trim();
      if (answer.isEmpty) {
        throw const ClaudeServiceException(
          'Claude returned an empty response.',
        );
      }
      return answer;
    } on DioException catch (error) {
      final responseData = error.response?.data;
      final apiError = responseData is Map ? responseData['error'] : null;
      final apiMessage = apiError is Map
          ? apiError['message']?.toString()
          : null;
      throw ClaudeServiceException(
        apiMessage ?? 'Claude request failed: ${error.message}',
      );
    }
  }
}
