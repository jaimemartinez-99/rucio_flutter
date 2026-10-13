import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rucio_flutter/models/claude_reading_context.dart';
import 'package:rucio_flutter/models/claude_retrieval.dart';
import 'package:rucio_flutter/models/claude_usage.dart';
import 'package:rucio_flutter/models/claude_mode.dart';
import 'package:rucio_flutter/providers/claude_mode_provider.dart';
import 'package:rucio_flutter/services/claude_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucio_flutter/providers/claude_provider.dart';
import 'package:rucio_flutter/widgets/claude_chat_sheet.dart';
import 'support/fake_claude_service.dart';

const contextFixture = ClaudeReadingContext(
  cutoffCfi: 'epubcfi(/6/2!/4/2/1:10)',
  sections: [ClaudeContextSection(href: 'one.xhtml', text: 'Already read.')],
  location: 'Chapter one',
  boundaryLabel: 'Hasta el final del fragmento seleccionado',
);

class FakeClaude extends ClaudeNotifier {
  FakeClaude(super.ref, super.bookId);

  final calls = <ClaudeReadingContext>[];
  final questions = <String>[];
  final modes = <ClaudeReadingMode>[];
  final previews = <ClaudePreparedQuestion?>[];
  Completer<void>? pending;

  @override
  Future<void> askQuestion(
    String? selectedText,
    String question, {
    required ClaudeReadingContext readingContext,
    ClaudeReadingMode mode = ClaudeReadingMode.economical,
    ClaudePreparedQuestion? preparedQuestion,
  }) async {
    calls.add(readingContext);
    questions.add(question);
    modes.add(mode);
    previews.add(preparedQuestion);
    state = state.copyWith(isLoading: true);
    if (pending != null) await pending!.future;
    state = ClaudeState(
      messages: [
        ClaudeMessage(
          question: question,
          answer: 'A supported explanation.',
          selection: selectedText,
          createdAt: DateTime(2026),
          usage: const ClaudeUsage(
            inputTokens: 100,
            outputTokens: 200,
            cacheReadTokens: 1000,
            estimatedUsd: 0.0024,
          ),
          model: 'claude-sonnet-5',
          boundaryLabel: readingContext.boundaryLabel,
          retrieval: preparedQuestion?.retrieval,
        ),
      ],
    );
  }

  @override
  Future<void> fetchHistory() async {
    state = ClaudeState(
      messages: [
        ClaudeMessage(
          question: 'Old question',
          answer: 'Old answer',
          createdAt: DateTime(2025),
        ),
      ],
    );
  }
}

Future<FakeClaude> openSheet(
  WidgetTester tester,
  Future<ClaudeReadingContext> Function() load, {
  FakeClaudeService? service,
  Map<String, Object> preferences = const {},
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  late FakeClaude notifier;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        claudeServiceProvider.overrideWithValue(service ?? FakeClaudeService()),
        claudeProvider.overrideWith(
          (ref, id) => notifier = FakeClaude(ref, id),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ClaudeChatSheet(
            bookId: 'book',
            loadReadingContext: load,
            boundaryLabel: contextFixture.boundaryLabel,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return notifier;
}

void main() {
  testWidgets(
    'Retrieved sources are reviewable before sending and remain with the answer',
    (tester) async {
      final service = FakeClaudeService()
        ..retrieval = ClaudeRetrieval(
          passages: const [
            ClaudeRetrievedPassage(
              id: 'F1',
              sectionIndex: 8,
              start: 0,
              end: 47,
              text: 'Catherine explica su decisión y Heathcliff se va.',
              chapterNumber: 9,
            ),
          ],
          sourceCharacters: 368858,
          sourceSections: 20,
          isComplete: false,
        );
      await openSheet(tester, () async => contextFixture, service: service);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '¿Por qué se va?');
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      expect(find.text('Búsqueda local · 1 pasaje'), findsOneWidget);
      await tester.tap(find.text('Búsqueda local · 1 pasaje'));
      await tester.pumpAndSettle();
      expect(find.text('[F1] Capítulo 9'), findsOneWidget);
      expect(
        find.text('Catherine explica su decisión y Heathcliff se va.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      expect(find.text('Búsqueda local · 1 pasaje'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Economic mode is the default and sending waits for a visible estimate',
    (tester) async {
      final service = FakeClaudeService();
      final notifier = await openSheet(
        tester,
        () async => contextFixture,
        service: service,
      );
      await tester.pumpAndSettle();
      expect(find.text('Económico · Haiku 5.5'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Explain this');
      tester.widget<TextField>(find.byType(TextField)).onSubmitted!(
        'Explain this',
      );
      await tester.pump();
      expect(notifier.calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      expect(find.textContaining('0,003548 USD'), findsOneWidget);
      expect(service.modes.single, ClaudeReadingMode.economical);
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      expect(notifier.modes.single, ClaudeReadingMode.economical);
      expect(notifier.previews.single!.question, 'Explain this');
    },
  );

  testWidgets(
    'Switching models invalidates the old estimate and persists the new choice',
    (tester) async {
      final service = FakeClaudeService();
      final notifier = await openSheet(
        tester,
        () async => contextFixture,
        service: service,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Explain this');
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<ClaudeReadingMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Análisis profundo · Sonnet 5.5').last);
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Send question',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      expect(find.textContaining('0,050480 USD'), findsOneWidget);
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      expect(notifier.modes.single, ClaudeReadingMode.deep);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(ClaudeModeNotifier.preferencesKey), 'deep');
    },
  );

  testWidgets('A saved mode is loaded before estimating', (tester) async {
    final service = FakeClaudeService();
    await openSheet(
      tester,
      () async => contextFixture,
      service: service,
      preferences: {ClaudeModeNotifier.preferencesKey: 'deep'},
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Explain this');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    expect(service.modes.single, ClaudeReadingMode.deep);
    expect(find.text('Análisis profundo · Sonnet 5.5'), findsOneWidget);
  });

  testWidgets('A failed estimate blocks generation and can be retried', (
    tester,
  ) async {
    final service = FakeClaudeService()..failPreparation = true;
    final notifier = await openSheet(
      tester,
      () async => contextFixture,
      service: service,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Explain this');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo estimar el coste'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Send question',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(notifier.calls, isEmpty);
    service.failPreparation = false;
    await tester.tap(find.text('Calcular'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Presupuesto estimado:'), findsOneWidget);
  });

  testWidgets('Late estimates cannot replace a newer question', (tester) async {
    final service = FakeClaudeService()..firstPreparation = Completer<void>();
    final notifier = await openSheet(
      tester,
      () async => contextFixture,
      service: service,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Old question');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'New question');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    service.firstPreparation!.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Send question'));
    await tester.pumpAndSettle();
    expect(notifier.questions.single, 'New question');
    expect(notifier.previews.single!.question, 'New question');
  });

  testWidgets('RAG previews stay below Haiku long context pricing', (
    tester,
  ) async {
    final service = FakeClaudeService()..inputTokens = 8600;
    await openSheet(tester, () async => contextFixture, service: service);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Explain this');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    expect(find.textContaining('0,003123 USD'), findsOneWidget);
    expect(find.textContaining('tarifa de contexto largo'), findsNothing);
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('Shows actual per-question usage and cost at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final notifier = await openSheet(tester, () async => contextFixture);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Explain this');
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      expect(find.textContaining('Presupuesto estimado:'), findsOneWidget);
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      expect(notifier.calls.single, same(contextFixture));
      expect(find.textContaining('1300 tokens'), findsOneWidget);
      expect(find.textContaining('0,002400 USD'), findsOneWidget);
      expect(find.text('Entrada: 1100'), findsOneWidget);
      expect(find.text('Salida: 200'), findsOneWidget);
      expect(find.text('Lectura de caché: 1000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('A missing context blocks sending and can be retried', (
    tester,
  ) async {
    var attempts = 0;
    final notifier = await openSheet(tester, () async {
      attempts++;
      if (attempts == 1) throw StateError('Invalid CFI');
      return contextFixture;
    });
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    expect(notifier.calls, isEmpty);
    expect(find.textContaining('no se enviará'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, true);
    expect(find.textContaining('Texto leído disponible'), findsOneWidget);
  });

  testWidgets('Keyboard submission cannot duplicate a pending paid question', (
    tester,
  ) async {
    final notifier = await openSheet(tester, () async => contextFixture);
    notifier.pending = Completer<void>();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Explain this');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    tester.widget<TextField>(find.byType(TextField)).onSubmitted!(
      'Explain this',
    );
    await tester.pump();
    expect(notifier.calls, hasLength(1));
    notifier.pending!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Closing the sheet during extraction does not update disposed widgets',
    (tester) async {
      final pending = Completer<ClaudeReadingContext>();
      await openSheet(tester, () => pending.future);
      await tester.pumpWidget(const SizedBox());
      pending.complete(contextFixture);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Historical questions without usage are not shown as free', (
    tester,
  ) async {
    await openSheet(tester, () async => contextFixture);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mostrar historial'));
    await tester.pumpAndSettle();
    expect(find.text('Consumo no registrado'), findsOneWidget);
    expect(find.textContaining('0,000000 USD'), findsNothing);
  });
}
