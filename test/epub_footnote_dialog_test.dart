import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rucio_flutter/models/epub_footnote.dart';
import 'package:rucio_flutter/widgets/epub_footnote_dialog.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('Long EPUB notes scroll and close at width ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final note = ValueNotifier<EpubFootnote?>(
        EpubFootnote(
          requestId: '1',
          label: '[17]',
          text: List.generate(
            200,
            (index) => 'Párrafo ${index + 1} de la nota del autor.',
          ).join('\n\n'),
        ),
      );
      addTearDown(note.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => EpubFootnoteDialog(footnote: note),
                ),
                child: const Text('Abrir nota'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir nota'));
      await tester.pumpAndSettle();
      expect(find.text('Nota [17]'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final scroll = find.byType(SingleChildScrollView);
      await tester.drag(scroll, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  }
}
