enum ClaudeReadingMode {
  economical('Económico', 'claude-haiku-5-5', 'Haiku 5.5', 4096),
  deep('Análisis profundo', 'claude-sonnet-5-5', 'Sonnet 5.5', 2048);

  const ClaudeReadingMode(
    this.label,
    this.modelId,
    this.modelLabel,
    this.maxOutputTokens,
  );

  final String label;
  final String modelId;
  final String modelLabel;
  final int maxOutputTokens;

  String get thinkingType => this == economical ? 'adaptive' : 'between_tools';
}

class ClaudePricing {
  const ClaudePricing({
    required this.input,
    required this.output,
    required this.cacheRead,
  });

  final double input;
  final double output;
  final double cacheRead;

  double cost({
    int inputTokens = 0,
    int outputTokens = 0,
    int cacheWrite5mTokens = 0,
    int cacheWrite1hTokens = 0,
    int cacheReadTokens = 0,
  }) =>
      (inputTokens * input +
          outputTokens * output +
          cacheWrite5mTokens * input * 1.25 +
          cacheWrite1hTokens * input * 2 +
          cacheReadTokens * cacheRead) /
      1000000;

  static ClaudePricing? forModel(String model, int totalInputTokens) =>
      switch (model) {
        'claude-haiku-5-5' =>
          totalInputTokens > 100000
              ? const ClaudePricing(input: 0.5, output: 2.5, cacheRead: 0.05)
              : const ClaudePricing(input: 0.1, output: 0.5, cacheRead: 0.01),
        'claude-sonnet-5-5' => const ClaudePricing(
          input: 2,
          output: 10,
          cacheRead: 0.1,
        ),
        'claude-sonnet-5' => const ClaudePricing(
          input: 2,
          output: 10,
          cacheRead: 0.2,
        ),
        _ => null,
      };
}
