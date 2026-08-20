import 'package:flutter/material.dart';

import '../services/translation_service.dart';

class TranslationSheet extends StatefulWidget {
  const TranslationSheet({super.key, required this.selectedText});

  final String selectedText;

  @override
  State<TranslationSheet> createState() => _TranslationSheetState();
}

class _TranslationSheetState extends State<TranslationSheet> {
  late final Future<String> _translation;

  @override
  void initState() {
    super.initState();
    _translation = TranslationService().translateEnglishToSpanish(
      widget.selectedText,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.translate, color: Color(0xFFf2a65a)),
                  const SizedBox(width: 10),
                  Text(
                    'Traducción al español',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Original', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Text(
                widget.selectedText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF7c748e),
                ),
              ),
              const Divider(height: 32),
              Text(
                'Español',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              FutureBuilder<String>(
                future: _translation,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text(
                            'Preparando la traducción local. La primera vez se descargarán los modelos.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Text(
                      'No se pudo traducir el texto: ${snapshot.error}',
                      style: const TextStyle(color: Color(0xFFf87171)),
                    );
                  }
                  return SelectableText(
                    snapshot.data ?? '',
                    style: Theme.of(context).textTheme.bodyLarge,
                  );
                },
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'Con tecnología de Google',
                  style: TextStyle(color: Color(0xFF7c748e), fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
