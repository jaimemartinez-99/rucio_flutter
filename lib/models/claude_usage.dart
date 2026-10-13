import 'claude_mode.dart';

class ClaudeUsage {
  const ClaudeUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheWrite5mTokens = 0,
    this.cacheWrite1hTokens = 0,
    this.cacheReadTokens = 0,
    this.estimatedUsd,
  });

  final int inputTokens;
  final int outputTokens;
  final int cacheWrite5mTokens;
  final int cacheWrite1hTokens;
  final int cacheReadTokens;
  final double? estimatedUsd;

  int get totalInputTokens =>
      inputTokens + cacheWrite5mTokens + cacheWrite1hTokens + cacheReadTokens;
  int get totalTokens => totalInputTokens + outputTokens;

  static ClaudeUsage? fromApi(Map<String, dynamic>? json, String model) {
    if (json == null ||
        json['input_tokens'] is! int ||
        json['output_tokens'] is! int) {
      return null;
    }
    int count(dynamic value) => value is int && value >= 0 ? value : 0;
    final input = count(json['input_tokens']);
    final output = count(json['output_tokens']);
    final read = count(json['cache_read_input_tokens']);
    final created = count(json['cache_creation_input_tokens']);
    final creation = json['cache_creation'];
    final hour = creation is Map
        ? count(creation['ephemeral_1h_input_tokens']).clamp(0, created)
        : 0;
    final fiveMinutes = created - hour;
    final cost = ClaudePricing.forModel(model, input + created + read)?.cost(
      inputTokens: input,
      outputTokens: output,
      cacheWrite5mTokens: fiveMinutes,
      cacheWrite1hTokens: hour,
      cacheReadTokens: read,
    );
    return ClaudeUsage(
      inputTokens: input,
      outputTokens: output,
      cacheWrite5mTokens: fiveMinutes,
      cacheWrite1hTokens: hour,
      cacheReadTokens: read,
      estimatedUsd: cost,
    );
  }

  Map<String, dynamic> toJson() => {
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    'cache_write_5m_tokens': cacheWrite5mTokens,
    'cache_write_1h_tokens': cacheWrite1hTokens,
    'cache_read_tokens': cacheReadTokens,
    'estimated_usd': estimatedUsd,
    'pricing_version': '2026-10-13',
  };

  static ClaudeUsage? fromJson(dynamic value) {
    if (value is! Map ||
        value['input_tokens'] is! int ||
        value['output_tokens'] is! int) {
      return null;
    }
    return ClaudeUsage(
      inputTokens: value['input_tokens'] as int,
      outputTokens: value['output_tokens'] as int,
      cacheWrite5mTokens: value['cache_write_5m_tokens'] as int? ?? 0,
      cacheWrite1hTokens: value['cache_write_1h_tokens'] as int? ?? 0,
      cacheReadTokens: value['cache_read_tokens'] as int? ?? 0,
      estimatedUsd: (value['estimated_usd'] as num?)?.toDouble(),
    );
  }
}
