import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/claude_provider.dart';
import '../models/claude_reading_context.dart';
import '../models/claude_retrieval.dart';
import '../models/claude_mode.dart';
import '../providers/claude_mode_provider.dart';
import '../services/claude_service.dart';
import 'claude_usage_summary.dart';

class ClaudeChatSheet extends ConsumerStatefulWidget {
  final String bookId;
  final String? selectedText;
  final Future<ClaudeReadingContext> Function() loadReadingContext;
  final String boundaryLabel;
  final ScrollController? scrollController;

  const ClaudeChatSheet({
    super.key,
    required this.bookId,
    this.selectedText,
    required this.loadReadingContext,
    required this.boundaryLabel,
    this.scrollController,
  });

  @override
  ConsumerState<ClaudeChatSheet> createState() => _ClaudeChatSheetState();
}

class _ClaudeChatSheetState extends ConsumerState<ClaudeChatSheet> {
  final _questionController = TextEditingController();
  late final ScrollController _scrollController;
  String? _error;
  var _isShowingHistory = false;
  var _isPreparingContext = true;
  ClaudeReadingContext? _readingContext;
  ClaudePreparedQuestion? _preparedQuestion;
  Timer? _estimateDebounce;
  CancelToken? _estimateCancel;
  int _estimateGeneration = 0;
  bool _isEstimating = false;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _questionController.addListener(_scheduleEstimate);
    Future.microtask(() {
      if (!mounted) return;
      ref.read(claudeProvider(widget.bookId).notifier).clearVisibleMessages();
      _prepareContext();
    });
  }

  Future<void> _prepareContext() async {
    _invalidateEstimate();
    setState(() {
      _isPreparingContext = true;
      _error = null;
      _readingContext = null;
    });
    try {
      await ref.read(claudeModeProvider.notifier).initialized;
      if (!mounted) return;
      final readingContext = await widget.loadReadingContext();
      if (!mounted) return;
      setState(() => _readingContext = readingContext);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error =
            'No se pudo adjuntar el texto leído: $error. La pregunta no se enviará sin un límite seguro.',
      );
    } finally {
      if (mounted) {
        setState(() => _isPreparingContext = false);
        _scheduleEstimate();
      }
    }
  }

  void _invalidateEstimate() {
    _estimateGeneration++;
    _estimateDebounce?.cancel();
    _estimateCancel?.cancel();
    _preparedQuestion = null;
    _isEstimating = false;
  }

  void _scheduleEstimate() {
    if (!mounted) return;
    setState(_invalidateEstimate);
    if (_readingContext == null ||
        _isPreparingContext ||
        _questionController.text.trim().isEmpty) {
      return;
    }
    _estimateDebounce = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_estimateQuestion()),
    );
  }

  Future<void> _estimateQuestion() async {
    if (_isEstimating) return;
    _estimateDebounce?.cancel();
    final readingContext = _readingContext;
    final question = _questionController.text.trim();
    if (readingContext == null || question.isEmpty) return;
    final generation = _estimateGeneration;
    final cancel = CancelToken();
    _estimateCancel = cancel;
    setState(() {
      _isEstimating = true;
      _error = null;
    });
    try {
      final prepared = await ref
          .read(claudeServiceProvider)
          .prepare(
            question,
            widget.selectedText,
            readingContext: readingContext,
            mode: ref.read(claudeModeProvider),
            cancelToken: cancel,
          );
      if (!mounted || generation != _estimateGeneration) return;
      setState(() => _preparedQuestion = prepared);
    } catch (error) {
      if (!mounted || generation != _estimateGeneration) return;
      setState(() => _error = 'No se pudo estimar el coste: $error');
    } finally {
      if (mounted && generation == _estimateGeneration) {
        setState(() => _isEstimating = false);
      }
    }
  }

  Future<void> _selectMode(ClaudeReadingMode mode) async {
    try {
      await ref.read(claudeModeProvider.notifier).select(mode);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'El modo se ha cambiado, pero no se pudo guardar la preferencia.',
        );
      }
    }
  }

  @override
  void dispose() {
    _invalidateEstimate();
    _questionController.dispose();
    if (widget.scrollController == null) _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendQuestion() async {
    final question = _questionController.text.trim();
    final readingContext = _readingContext;
    final prepared = _preparedQuestion;
    if (question.isEmpty ||
        readingContext == null ||
        _isPreparingContext ||
        _isEstimating ||
        prepared == null ||
        prepared.question != question ||
        prepared.mode != ref.read(claudeModeProvider) ||
        ref.read(claudeProvider(widget.bookId)).isLoading) {
      return;
    }

    setState(() => _error = null);

    try {
      await ref
          .read(claudeProvider(widget.bookId).notifier)
          .askQuestion(
            widget.selectedText,
            question,
            readingContext: readingContext,
            mode: prepared.mode,
            preparedQuestion: prepared,
          );
      if (!mounted) return;
      _questionController.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _showHistory() async {
    setState(() => _isShowingHistory = true);
    await ref.read(claudeProvider(widget.bookId).notifier).fetchHistory();
    if (!mounted) return;
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(claudeProvider(widget.bookId));
    final mode = ref.watch(claudeModeProvider);
    ref.listen(claudeModeProvider, (_, _) => _scheduleEstimate());

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF7C748E),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFF10B981),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ask Claude',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      _isShowingHistory ||
                          state.isLoading ||
                          _isPreparingContext
                      ? null
                      : _showHistory,
                  icon: const Icon(Icons.history_outlined, size: 18),
                  label: const Text('Mostrar historial'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: DropdownButtonFormField<ClaudeReadingMode>(
              key: ValueKey(mode),
              initialValue: mode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Modo de respuesta'),
              items: [
                for (final option in ClaudeReadingMode.values)
                  DropdownMenuItem(
                    value: option,
                    child: Text(
                      '${option.label} · ${option.modelLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: state.isLoading || _isPreparingContext
                  ? null
                  : (value) {
                      if (value != null) unawaited(_selectMode(value));
                    },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 18,
                  color: Color(0xFF10B981),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isPreparingContext
                        ? 'Preparando el texto leído…'
                        : _readingContext == null
                        ? 'No se ha podido preparar el contexto'
                        : 'Texto leído disponible · ${_readingContext!.positionSummary}\n${widget.boundaryLabel}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (!_isPreparingContext && _readingContext == null)
                  TextButton(
                    onPressed: _prepareContext,
                    child: const Text('Reintentar'),
                  ),
              ],
            ),
          ),
          if (widget.selectedText != null &&
              widget.selectedText!.trim().isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF252336),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Using selected text: ${widget.selectedText!.trim()}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFFB7B0C6)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    enabled:
                        !_isPreparingContext &&
                        _readingContext != null &&
                        !state.isLoading,
                    decoration: const InputDecoration(
                      hintText: 'Ask Claude...',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendQuestion(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed:
                      state.isLoading ||
                          _isPreparingContext ||
                          _readingContext == null ||
                          _isEstimating ||
                          _preparedQuestion == null
                      ? null
                      : _sendQuestion,
                  icon: const Icon(Icons.send),
                  tooltip: 'Send question',
                ),
              ],
            ),
          ),
          if (_questionController.text.trim().isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF252336),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _preparedQuestion == null
                  ? Row(
                      children: [
                        if (_isEstimating)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        if (_isEstimating) const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isEstimating
                                ? 'Buscando pasajes y calculando coste…'
                                : 'Coste pendiente de calcular',
                          ),
                        ),
                        if (!_isEstimating)
                          TextButton(
                            onPressed: _estimateQuestion,
                            child: const Text('Calcular'),
                          ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Presupuesto estimado: ${_preparedQuestion!.estimatedMaxUsd.toStringAsFixed(6).replaceAll('.', ',')} USD',
                        ),
                        Text(
                          '${_preparedQuestion!.inputTokens} tokens de entrada · hasta ${mode.maxOutputTokens} de salida${mode == ClaudeReadingMode.economical ? ' (razonamiento y respuesta)' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          'Con caché nueva; reutilizarla puede reducir el coste.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_preparedQuestion!.retrieval != null)
                          _RetrievedPassages(
                            retrieval: _preparedQuestion!.retrieval!,
                          ),
                        if (_preparedQuestion!.usesLongContextPrice)
                          Text(
                            'Haiku aplica tarifa de contexto largo (>100.000 tokens).',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
            ),
          if (state.messages.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Ask a question about this book.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          for (final message in state.messages)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _MessageBubble(message: message),
            ),
          if (state.isLoading || _isPreparingContext)
            const LinearProgressIndicator(),
          if (_error != null || state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _error ?? state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ClaudeMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withAlpha(40),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Text(message.question),
          ),
          const SizedBox(height: 8),
          MarkdownBody(
            data: message.answer,
            styleSheet: MarkdownStyleSheet(
              p: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (message.warning != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                message.warning!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          ClaudeUsageSummary(usage: message.usage, model: message.model),
          if (message.retrieval != null)
            _RetrievedPassages(retrieval: message.retrieval!)
          else if (message.sources.isNotEmpty)
            Text(
              'Fuentes: ${message.sources.join(' · ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (message.boundaryLabel != null)
            Text(
              message.boundaryLabel!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _RetrievedPassages extends StatelessWidget {
  const _RetrievedPassages({required this.retrieval});

  final ClaudeRetrieval retrieval;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        title: Text(
          'Búsqueda local · ${retrieval.passages.length} ${retrieval.passages.length == 1 ? 'pasaje' : 'pasajes'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        subtitle: Text(
          '${retrieval.retrievedCharacters} de ${retrieval.sourceCharacters} caracteres de texto leído',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        children: [
          for (final passage in retrieval.passages)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '[${passage.id}] ${passage.label}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    passage.text.trim(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
