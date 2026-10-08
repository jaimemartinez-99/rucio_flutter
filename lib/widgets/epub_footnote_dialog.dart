import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/epub_footnote.dart';

class EpubFootnoteDialog extends StatelessWidget {
  const EpubFootnoteDialog({super.key, required this.footnote});

  final ValueListenable<EpubFootnote?> footnote;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<EpubFootnote?>(
    valueListenable: footnote,
    builder: (context, note, _) => AlertDialog(
      title: Text(
        note == null || note.label.isEmpty
            ? 'Nota del libro'
            : 'Nota ${note.label}',
      ),
      content: SizedBox(
        width: 560,
        child: note == null || note.isLoading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Leyendo nota…'),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: SelectableText(
                  note.error ?? note.text ?? 'Esta nota no contiene texto.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}
