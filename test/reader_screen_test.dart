import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucio_flutter/models/highlight.dart';
import 'package:rucio_flutter/providers/highlights_provider.dart';
import 'package:rucio_flutter/providers/notes_provider.dart';
import 'package:rucio_flutter/providers/progress_provider.dart';
import 'package:rucio_flutter/screens/reader_screen.dart';
import 'package:rucio_flutter/services/reader_content_loader.dart';
import 'package:rucio_flutter/services/reader_webview.dart';

class FakeReaderWebView implements ReaderWebView {
  final events = StreamController<ReaderWebMessage>.broadcast(sync: true);
  final failures = StreamController<String>.broadcast(sync: true);
  final scripts = <String>[];
  bool disposed = false;

  @override
  Stream<ReaderWebMessage> get messages => events.stream;

  @override
  Stream<String> get errors => failures.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> loadHtml(String html) async {
    events.add(const ReaderWebMessage('ReaderReady', ''));
  }

  @override
  Future<void> runJavaScript(String script) async => scripts.add(script);

  @override
  Widget buildView() => const SizedBox.expand(key: Key('reader-webview'));

  @override
  Future<void> dispose() async {
    disposed = true;
    await events.close();
    await failures.close();
  }

  void select(
    String action, {
    String text = 'A passage',
    String cfi = 'epubcfi(/6/2!/4/2:0,/1:0,/1:9)',
  }) {
    events.add(
      ReaderWebMessage(
        'SelectionAction',
        jsonEncode({'action': action, 'text': text, 'cfiRange': cfi}),
      ),
    );
  }
}

class FakeContentLoader implements ReaderContentLoader {
  @override
  Future<ReaderContent> load(String bookId) async =>
      const ReaderContent(html: '<html></html>');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecordingHighlights extends HighlightsNotifier {
  RecordingHighlights(super.ref) : super(bookId: 'book');

  final saved = <({String cfi, String text, String color})>[];
  bool failSave = false;

  @override
  Future<void> fetchHighlights() async {}

  @override
  Future<void> addHighlight(
    String cfiRange,
    String text, {
    String color = '#ffff00',
    String? note,
  }) async {
    if (failSave) throw StateError('Network unavailable');
    saved.add((cfi: cfiRange, text: text, color: color));
  }
}

class FakeNotes extends NotesNotifier {
  FakeNotes(super.ref) : super(bookId: 'book');

  @override
  Future<void> fetchNotes({bool includeBooks = false}) async {}
}

class FakeProgress extends ProgressNotifier {
  FakeProgress(Ref ref) : super(ref, 'book');

  @override
  Future<void> fetchProgress() async {}

  @override
  Future<void> flushProgress() async {}
}

Future<RecordingHighlights> openReader(
  WidgetTester tester,
  FakeReaderWebView view,
  Size size,
) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late RecordingHighlights highlights;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        readerContentLoaderProvider.overrideWithValue(FakeContentLoader()),
        readerWebViewFactoryProvider.overrideWithValue(() => view),
        bookHighlightsProvider.overrideWith(
          (ref, bookId) => highlights = RecordingHighlights(ref),
        ),
        bookNotesProvider.overrideWith((ref, bookId) => FakeNotes(ref)),
        progressProvider.overrideWith((ref, bookId) => FakeProgress(ref)),
      ],
      child: const MaterialApp(home: ReaderScreen(bookId: 'book')),
    ),
  );
  await tester.pumpAndSettle();
  return highlights;
}

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets(
      'EPUB footnotes open without moving the reader at width ${size.width}',
      (tester) async {
        final view = FakeReaderWebView();
        await openReader(tester, view, size);
        view.scripts.clear();
        view.events.add(
          ReaderWebMessage(
            'Footnote',
            jsonEncode({'requestId': '1', 'label': '[1]', 'loading': true}),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Nota [1]'), findsOneWidget);
        expect(find.text('Leyendo nota…'), findsOneWidget);
        view.events.add(
          ReaderWebMessage(
            'Footnote',
            jsonEncode({
              'requestId': '1',
              'label': '[1]',
              'text': 'La explicación del autor.\n\nOtro párrafo.',
            }),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('La explicación del autor.\n\nOtro párrafo.'),
          findsOneWidget,
        );
        expect(find.text('Leyendo nota…'), findsNothing);
        expect(view.scripts, isEmpty);
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byKey(const Key('reader-webview')), findsOneWidget);
        expect(view.scripts, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        expect(view.scripts, ['prevPage()']);
        await tester.pumpWidget(const SizedBox());
      },
    );

    for (final option in HighlightColorOption.values) {
      testWidgets(
        'Choosing ${option.label} saves its type at width ${size.width}',
        (tester) async {
          final view = FakeReaderWebView();
          final highlights = await openReader(tester, view, size);
          view.scripts.clear();

          view.select('highlight');
          await tester.pumpAndSettle();
          expect(highlights.saved, isEmpty);
          expect(view.scripts, isEmpty);
          expect(find.text('Tipo de highlight'), findsOneWidget);

          await tester.tap(find.text(option.label));
          await tester.pumpAndSettle();
          expect(highlights.saved.single.color, option.value);
          expect(highlights.saved.single.text, 'A passage');
          expect(highlights.saved.single.cfi, 'epubcfi(/6/2!/4/2:0,/1:0,/1:9)');
          expect(view.scripts.single, contains(option.value));
          expect(find.text('Highlight guardado'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets(
      'Dismissing the type picker never saves at width ${size.width}',
      (tester) async {
        final view = FakeReaderWebView();
        final highlights = await openReader(tester, view, size);
        view.scripts.clear();
        view.select('highlight');
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(highlights.saved, isEmpty);
        expect(view.scripts, isEmpty);
        await tester.pumpWidget(const SizedBox());
        expect(view.disposed, isTrue);
      },
    );
  }

  testWidgets('Closing a pending footnote ignores its delayed response', (
    tester,
  ) async {
    final view = FakeReaderWebView();
    await openReader(tester, view, const Size(390, 844));
    view.events.add(
      ReaderWebMessage(
        'Footnote',
        jsonEncode({'requestId': '1', 'label': '[1]', 'loading': true}),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    view.events.add(
      ReaderWebMessage(
        'Footnote',
        jsonEncode({'requestId': '1', 'label': '[1]', 'text': 'Late note.'}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Older footnote responses cannot replace a newer note', (
    tester,
  ) async {
    final view = FakeReaderWebView();
    await openReader(tester, view, const Size(1280, 800));
    for (final id in ['1', '2']) {
      view.events.add(
        ReaderWebMessage(
          'Footnote',
          jsonEncode({'requestId': id, 'label': '[$id]', 'loading': true}),
        ),
      );
    }
    view.events.add(
      ReaderWebMessage(
        'Footnote',
        jsonEncode({'requestId': '1', 'label': '[1]', 'text': 'Older note.'}),
      ),
    );
    view.events.add(
      ReaderWebMessage(
        'Footnote',
        jsonEncode({
          'requestId': '2',
          'label': '[2]',
          'error': 'No se pudo leer la nota del EPUB.',
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Nota [2]'), findsOneWidget);
    expect(find.text('Older note.'), findsNothing);
    expect(find.text('No se pudo leer la nota del EPUB.'), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    view.scripts.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(view.scripts, ['nextPage()']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A failed save does not render or report a saved highlight', (
    tester,
  ) async {
    final view = FakeReaderWebView();
    final highlights = await openReader(tester, view, const Size(1280, 800));
    highlights.failSave = true;
    view.scripts.clear();
    view.select('highlight');
    await tester.pumpAndSettle();
    await tester.tap(find.text(HighlightColorOption.beautiful.label));
    await tester.pumpAndSettle();
    expect(view.scripts, isEmpty);
    expect(
      find.textContaining('No se pudo guardar el highlight:'),
      findsOneWidget,
    );
    expect(find.text('Highlight guardado'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Page shortcuts and toolbar visibility use the common renderer', (
    tester,
  ) async {
    final view = FakeReaderWebView();
    await openReader(tester, view, const Size(1280, 800));
    view.scripts.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(view.scripts, ['nextPage()', 'prevPage()']);
    view.events.add(const ReaderWebMessage('ToggleUI', ''));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    view.events.add(const ReaderWebMessage('ToggleUI', ''));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
