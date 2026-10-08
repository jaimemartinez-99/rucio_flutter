import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rucio_flutter/models/book.dart';
import 'package:rucio_flutter/models/epub_metadata.dart';
import 'package:rucio_flutter/services/epub_metadata_service.dart';
import 'package:rucio_flutter/widgets/book_info_dialog.dart';

class _MetadataService implements EpubMetadataService {
  int attempts = 0;
  bool failFirst = false;
  EpubMetadata data = const EpubMetadata();

  @override
  Future<EpubMetadata> load(Book book) async {
    attempts++;
    if (failFirst && attempts == 1) throw StateError('Offline');
    return data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _openInfo(
  WidgetTester tester,
  _MetadataService service,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [epubMetadataServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => BookInfoDialog(
                  book: Book(
                    id: 'book',
                    userId: 'user',
                    title: 'Título de biblioteca',
                    author: 'Autor',
                    createdAt: DateTime(2026),
                  ),
                ),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets(
      'Long EPUB information scrolls and closes at width ${size.width}',
      (tester) async {
        final service = _MetadataService()
          ..data = EpubMetadata(
            title: 'Título del EPUB',
            authors: ['Autora'],
            pageCount: 554,
            pageCountSource: EpubPageCountSource.metadata,
            description: List.filled(
              100,
              'Una sinopsis larga que se puede leer.',
            ).join('\n'),
          );
        await _openInfo(tester, service, size);
        expect(find.text('Título del EPUB'), findsOneWidget);
        expect(find.text('554'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();
        expect(find.byType(BookInfoDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Metadata can be retried and missing pages are explicit', (
    tester,
  ) async {
    final service = _MetadataService()..failFirst = true;
      await _openInfo(tester, service, const Size(390, 844));
    expect(find.text('Título de biblioteca'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(service.attempts, 2);
    expect(find.text('No indicado en el EPUB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
