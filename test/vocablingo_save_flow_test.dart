import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rucio_flutter/services/vocablingo_service.dart';
import 'package:rucio_flutter/widgets/vocablingo_save_flow.dart';

class FakeVocablingoService implements VocablingoService {
  @override
  bool isAuthenticated = false;

  int signInAttempts = 0;
  String? email;
  String? password;
  String? savedSelection;
  Object? signInError;
  Object? saveError;
  Completer<void>? signInPending;
  Completer<void>? savePending;
  String resultType = 'word';
  String definition =
      '1. Conjunto de muchas hojas de papel encuadernadas.\n2. Obra científica o literaria.';

  @override
  Future<void> signIn(String email, String password) async {
    signInAttempts++;
    this.email = email;
    this.password = password;
    if (signInError != null) throw signInError!;
    await signInPending?.future;
    isAuthenticated = true;
  }

  @override
  Future<Map<String, dynamic>> saveSelection(String selection) async {
    savedSelection = selection;
    if (saveError != null) throw saveError!;
    await savePending?.future;
    return {
      'type': resultType,
      'text': selection,
      if (resultType == 'word') 'definition': definition,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> openSaveFlow(
  WidgetTester tester,
  FakeVocablingoService service, {
  String selection = 'libro',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => saveToVocablingo(
              context,
              service: service,
              selection: selection,
              email: 'reader@example.com',
            ),
            child: const Text('Vocablingo'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Vocablingo'));
  await tester.pumpAndSettle();
}

void main() {
  for (final type in ['word', 'phrase']) {
    testWidgets('Authenticated $type saves without requesting credentials', (
      tester,
    ) async {
      final service = FakeVocablingoService()
        ..isAuthenticated = true
        ..resultType = type;
      final selection = type == 'word' ? 'libro' : 'un buen libro';

      await openSaveFlow(tester, service, selection: selection);

      expect(service.signInAttempts, 0);
      expect(service.savedSelection, selection);
      if (type == 'word') {
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Definición de $selection'), findsOneWidget);
        expect(find.text(service.definition), findsOneWidget);
        expect(find.byType(SelectableText), findsOneWidget);
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      } else {
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Frase guardada: $selection'), findsOneWidget);
      }
    });
  }

  testWidgets('Long definitions can be read and closed on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeVocablingoService()
      ..isAuthenticated = true
      ..definition = List.generate(
        40,
        (index) => '${index + 1}. Una acepción de la palabra.',
      ).join('\n');

    await openSaveFlow(tester, service);
    expect(find.text(service.definition), findsOneWidget);
    expect(tester.takeException(), isNull);
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel and empty credentials never save a selection', (
    tester,
  ) async {
    final service = FakeVocablingoService();
    await openSaveFlow(tester, service);

    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Introduce tu contraseña.'), findsOneWidget);
    expect(service.signInAttempts, 0);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.savedSelection, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sign-in failure can be retried with the original selection', (
    tester,
  ) async {
    final service = FakeVocablingoService()
      ..signInError = const VocablingoException('Invalid login credentials');
    await openSaveFlow(tester, service, selection: 'un buen libro');
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'reader@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'test-password');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Invalid login credentials'), findsOneWidget);
    expect(service.savedSelection, isNull);

    service.signInError = null;
    service.signInPending = Completer<void>();
    service.resultType = 'phrase';
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNull,
    );
    expect(service.savedSelection, isNull);

    service.signInPending!.complete();
    await tester.pumpAndSettle();
    expect(service.signInAttempts, 2);
    expect(service.email, 'reader@example.com');
    expect(service.password, 'test-password');
    expect(service.savedSelection, 'un buen libro');
    expect(find.text('Frase guardada: un buen libro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Save failures display the error instead of reporting success', (
    tester,
  ) async {
    final service = FakeVocablingoService()
      ..isAuthenticated = true
      ..saveError = const VocablingoException('Dictionary unavailable');
    await openSaveFlow(tester, service);

    expect(
      find.text('No se pudo guardar en Vocablingo: Dictionary unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('guardadas:'), findsNothing);
  });

  testWidgets(
    'Leaving the reader during a save does not use disposed context',
    (tester) async {
      final service = FakeVocablingoService()
        ..isAuthenticated = true
        ..savePending = Completer<void>();
      await openSaveFlow(tester, service);
      await tester.pumpWidget(const SizedBox());
      service.savePending!.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
