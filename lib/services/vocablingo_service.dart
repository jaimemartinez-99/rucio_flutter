import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart';

class VocablingoException implements Exception {
  const VocablingoException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VocablingoService {
  static final VocablingoService _instance = VocablingoService._internal();

  factory VocablingoService() => _instance;

  VocablingoService._internal()
    : client = SupabaseClient(
        dotenv.get('VOCABLINGO_SUPABASE_URL'),
        dotenv.get('VOCABLINGO_SUPABASE_ANON_KEY'),
      ),
      _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

  final SupabaseClient client;
  final Dio _dio;

  bool get isAuthenticated => client.auth.currentUser != null;

  Future<void> signIn(String email, String password) async {
    try {
      await client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (error) {
      throw VocablingoException(error.message);
    }
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  Future<Map<String, dynamic>> saveSelection(String selection) async {
    final text = _normalizeSelection(selection);
    if (text.isEmpty) {
      throw const VocablingoException('Select a word or phrase before saving.');
    }
    return _isSingleWord(text) ? saveWord(text) : savePhrase(text);
  }

  Future<Map<String, dynamic>> saveWord(String word) async {
    final userId = _requireUserId();
    final normalizedWord = _normalizeSelection(word);
    if (!_isSingleWord(normalizedWord)) {
      throw const VocablingoException(
        'Please select a single word to save a definition.',
      );
    }

    final definition = await _fetchRaeDefinition(normalizedWord);
    await client.from('vocabulary').insert({
      'word': normalizedWord,
      'definition': definition,
      'user_id': userId,
    });
    return {'type': 'word', 'text': normalizedWord, 'definition': definition};
  }

  Future<Map<String, dynamic>> savePhrase(String phrase) async {
    final userId = _requireUserId();
    final normalizedPhrase = _normalizeSelection(phrase);
    if (normalizedPhrase.isEmpty) {
      throw const VocablingoException('Select a phrase before saving.');
    }

    await client.from('saved_phrases').insert({
      'phrase': normalizedPhrase,
      'user_id': userId,
    });
    return {'type': 'phrase', 'text': normalizedPhrase};
  }

  String _requireUserId() {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw const VocablingoException('Sign in to Vocablingo before saving.');
    }
    return userId;
  }

  Future<String> _fetchRaeDefinition(String word) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://rae-api.com/api/words/${Uri.encodeComponent(word.toLowerCase())}',
      );
      final body = response.data;
      if (body == null || body['ok'] != true) {
        throw VocablingoException('No RAE definition was found for "$word".');
      }

      final data = body['data'];
      final meanings = data is Map ? data['meanings'] : null;
      if (meanings is! List) {
        throw VocablingoException('No RAE definition was found for "$word".');
      }

      final definitions = <String>[];
      for (final meaning in meanings.whereType<Map>()) {
        final senses = meaning['senses'];
        if (senses is! List) continue;
        for (final sense in senses.whereType<Map>()) {
          final number = sense['meaning_number']?.toString() ?? '?';
          final text =
              (sense['description'] ??
                      sense['raw'] ??
                      sense['definition'] ??
                      '')
                  .toString()
                  .trim();
          if (text.isNotEmpty) definitions.add('$number. $text');
        }
      }

      if (definitions.isEmpty) {
        throw VocablingoException('No RAE definition was found for "$word".');
      }
      return definitions.join('\n');
    } on DioException catch (error) {
      if (error.response?.statusCode == 429) {
        throw const VocablingoException(
          'RAE lookup limit reached. Please try again shortly.',
        );
      }
      throw const VocablingoException(
        'Could not reach the RAE dictionary. Please try again.',
      );
    }
  }

  String _normalizeSelection(String value) {
    return value
        .trim()
        .replaceFirst(RegExp(r'^[.,;:!?¿¡"“”‘’()\[\]{}]+'), '')
        .replaceFirst(RegExp(r'[.,;:!?¿¡"“”‘’()\[\]{}]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isSingleWord(String value) => !value.contains(RegExp(r'\s'));
}

final vocablingoServiceProvider = Provider<VocablingoService>((ref) {
  return VocablingoService();
});
