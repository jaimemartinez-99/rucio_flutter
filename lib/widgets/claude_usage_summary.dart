import 'package:flutter/material.dart';

import '../models/claude_usage.dart';

class ClaudeUsageSummary extends StatelessWidget {
  const ClaudeUsageSummary({super.key, required this.usage, this.model});

  final ClaudeUsage? usage;
  final String? model;

  @override
  Widget build(BuildContext context) {
    final usage = this.usage;
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: const Color(0xFFB7B0C6));
    if (usage == null) return Text('Consumo no registrado', style: style);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF252336),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${usage.totalTokens} tokens · ${usage.estimatedUsd == null ? 'Coste no disponible' : 'Coste estimado: ${usage.estimatedUsd!.toStringAsFixed(6).replaceAll('.', ',')} USD'}',
            style: style,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text('Entrada: ${usage.totalInputTokens}', style: style),
              Text('Salida: ${usage.outputTokens}', style: style),
              if (usage.cacheWrite5mTokens + usage.cacheWrite1hTokens > 0)
                Text(
                  'Escritura de caché: ${usage.cacheWrite5mTokens + usage.cacheWrite1hTokens}',
                  style: style,
                ),
              if (usage.cacheReadTokens > 0)
                Text(
                  'Lectura de caché: ${usage.cacheReadTokens}',
                  style: style,
                ),
            ],
          ),
          if (model != null) Text(model!, style: style),
        ],
      ),
    );
  }
}
