import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/book.dart';
import '../models/epub_metadata.dart';
import '../services/epub_metadata_service.dart';

class BookInfoDialog extends ConsumerStatefulWidget {
  const BookInfoDialog({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<BookInfoDialog> createState() => _BookInfoDialogState();
}

class _BookInfoDialogState extends ConsumerState<BookInfoDialog> {
  late Future<EpubMetadata> _metadata;

  @override
  void initState() {
    super.initState();
    _metadata = ref.read(epubMetadataServiceProvider).load(widget.book);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Información del libro'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: FutureBuilder<EpubMetadata>(
            future: _metadata,
            builder: (context, snapshot) {
              final data = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(
                    data?.title ?? widget.book.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  _field(
                    'Autor',
                    data != null && data.authors.isNotEmpty
                        ? data.authors.join(', ')
                        : widget.book.author ?? 'No indicado',
                  ),
                  if (snapshot.connectionState != ConnectionState.done) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    const Text('Leyendo la información del EPUB…'),
                  ] else if (snapshot.hasError) ...[
                    const Text(
                      'No se ha podido leer la información del EPUB. Comprueba la conexión si el libro aún no está descargado.',
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _metadata = ref
                            .read(epubMetadataServiceProvider)
                            .load(widget.book);
                      }),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ] else if (data != null) ...[
                    _field(
                      data.pageCountSource == EpubPageCountSource.pageList
                          ? 'Páginas referenciadas'
                          : 'Páginas',
                      data.pageCount?.toString() ?? 'No indicado en el EPUB',
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        data.pageCountSource == EpubPageCountSource.pageList
                            ? 'Recuento de las páginas incluidas en el índice de páginas del EPUB.'
                            : 'Las páginas del lector pueden variar según la pantalla y el tamaño de letra.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (data.contributors.isNotEmpty)
                      _field('Colaboradores', data.contributors.join(', ')),
                    if (data.publisher != null)
                      _field('Editorial', data.publisher!),
                    if (data.languages.isNotEmpty)
                      _field(
                        'Idioma',
                        data.languages.map(_language).join(', '),
                      ),
                    if (data.publicationDate != null)
                      _field(
                        'Fecha de publicación',
                        _date(data.publicationDate!),
                      ),
                    if (data.series != null) _field('Colección', data.series!),
                    if (data.identifiers.isNotEmpty)
                      _field(
                        'Identificadores / ISBN',
                        data.identifiers.join('\n'),
                      ),
                    if (data.subjects.isNotEmpty)
                      _field('Temas', data.subjects.join(' · ')),
                    if (data.description != null)
                      _field('Sinopsis', data.description!),
                  ],
                  if ((data?.fileSize ?? widget.book.fileSize)
                      case final int size)
                    _field(
                      'Tamaño del EPUB',
                      size >= 1024 * 1024
                          ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
                          : '${(size / 1024).toStringAsFixed(1)} KB',
                    ),
                ],
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    ),
  );

  String _language(String code) {
    final name = const {
      'es': 'Español',
      'spa': 'Español',
      'en': 'Inglés',
      'eng': 'Inglés',
      'fr': 'Francés',
      'fra': 'Francés',
      'de': 'Alemán',
      'deu': 'Alemán',
      'it': 'Italiano',
      'ita': 'Italiano',
      'pt': 'Portugués',
      'por': 'Portugués',
      'ca': 'Catalán',
      'cat': 'Catalán',
      'gl': 'Gallego',
      'eu': 'Euskera',
    }[code.toLowerCase().split(RegExp('[-_]')).first];
    return name == null ? code : '$name ($code)';
  }

  String _date(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    return match == null ? value : '${match[3]}/${match[2]}/${match[1]}';
  }
}
