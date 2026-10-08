import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/epub_footnote.dart';
import '../models/audio_page.dart';
import '../providers/audiorucio_provider.dart';
import '../providers/highlights_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/settings_provider.dart';
import '../services/reader_content_loader.dart';
import '../services/reader_webview.dart';
import '../services/vocablingo_service.dart';
import '../services/google_tts_service.dart';
import '../widgets/audiorucio_player.dart';
import '../widgets/claude_chat_sheet.dart';
import '../widgets/epub_footnote_dialog.dart';
import '../widgets/highlight_type_picker.dart';
import '../widgets/note_editor_sheet.dart';
import '../widgets/search_panel.dart';
import '../widgets/settings_panel.dart';
import '../widgets/toc_drawer.dart';
import '../widgets/translation_sheet.dart';
import '../widgets/vocablingo_save_flow.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.bookId, this.initialCfi});

  final String bookId;
  final String? initialCfi;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  ReaderContent? _readerContent;
  ReaderWebView? _webViewController;
  StreamSubscription<ReaderWebMessage>? _messageSubscription;
  StreamSubscription<String>? _errorSubscription;
  late final ProgressNotifier _progressNotifier;
  Timer? _readingTimer;
  DateTime? _readingStartedAt;
  Duration _sessionReadingTime = Duration.zero;
  double _progress = 0;
  String? _currentCfi;
  String? _currentHref;
  List<TocItem> _tocItems = [];
  bool _isLoading = true;
  String? _loadError;
  bool _showChrome = true;
  bool _showSearch = false;
  String _searchQuery = '';
  final List<SearchResult> _searchResults = [];
  final GlobalKey<SearchPanelState> _searchPanelKey = GlobalKey();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _readerFocusNode = FocusNode();
  final _footnote = ValueNotifier<EpubFootnote?>(null);
  bool _footnoteDialogOpen = false;
  AudioSession? _audioSession;
  final _readerViewportKey = GlobalKey();
  Size? _audioReaderSize;
  int _audioRequestId = 0;
  final Map<int, Completer<AudioPage?>> _audioRequests = {};

  @override
  void initState() {
    super.initState();
    _progressNotifier = ref.read(progressProvider(widget.bookId).notifier);
    if (Platform.isAndroid) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
    }
    unawaited(_loadBook());
  }

  Future<void> _loadBook() async {
    ReaderWebView? controller;
    try {
      final content = await ref
          .read(readerContentLoaderProvider)
          .load(widget.bookId);
      if (!mounted) {
        await content.dispose();
        return;
      }
      _readerContent = content;
      controller = ref.read(readerWebViewFactoryProvider)();
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _webViewController = controller;
      _messageSubscription = controller.messages.listen(_onWebMessage);
      _errorSubscription = controller.errors.listen(_setLoadError);
      setState(() {});
      await controller.loadHtml(content.html);
    } catch (error) {
      await _messageSubscription?.cancel();
      await _errorSubscription?.cancel();
      await controller?.dispose();
      _webViewController = null;
      await _readerContent?.dispose();
      _readerContent = null;
      _setLoadError('No se pudo abrir el libro: $error');
    }
  }

  void _onWebMessage(ReaderWebMessage event) {
    if (!mounted) return;
    try {
      final message = event.message;
      switch (event.channel) {
        case 'AudioPage':
          final data = jsonDecode(message) as Map<String, dynamic>;
          final request = _audioRequests.remove(data['requestId']);
          if (request == null) return;
          if (data['error'] is String) {
            request.completeError(AudioRucioException(data['error'] as String));
          } else {
            final page = data['page'];
            request.complete(
              page == null
                  ? null
                  : AudioPage.fromJson(page as Map<String, dynamic>),
            );
          }
        case 'ReaderReady':
          unawaited(_onReaderReady());
        case 'Relocated':
          final data = jsonDecode(message) as Map<String, dynamic>;
          final cfi = data['cfi'] as String? ?? '';
          final percentage = (data['percentage'] as num?)?.toDouble() ?? 0;
          setState(() {
            _currentCfi = cfi;
            _currentHref = data['href'] as String?;
            _progress = percentage;
          });
          _progressNotifier.saveProgress(cfi, percentage);
        case 'Toc':
          final data = jsonDecode(message) as List<dynamic>;
          setState(() {
            _tocItems = data
                .map((item) => TocItem.fromJson(item as Map<String, dynamic>))
                .toList();
          });
        case 'SearchResults':
          final data = jsonDecode(message) as List<dynamic>;
          final results = data
              .map(
                (item) => SearchResult.fromJson(item as Map<String, dynamic>),
              )
              .toList();
          setState(() {
            _searchResults
              ..clear()
              ..addAll(results);
          });
          _searchPanelKey.currentState?.updateResults(results);
        case 'SelectionAction':
          unawaited(_onSelectionAction(message));
        case 'NoteTapped':
          _openNote(message);
        case 'Footnote':
          _onFootnote(message);
        case 'ToggleUI':
          if (_audioSession == null) _toggleAppBar();
        case 'ReaderError':
          _setLoadError(message);
      }
    } catch (error) {
      _showMessage('No se pudo procesar la acción del lector: $error');
    }
  }

  void _onFootnote(String message) {
    final note = EpubFootnote.fromJson(
      jsonDecode(message) as Map<String, dynamic>,
    );
    if (note.isLoading) {
      _footnote.value = note;
      if (_footnoteDialogOpen) return;
      _footnoteDialogOpen = true;
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => EpubFootnoteDialog(footnote: _footnote),
        ).whenComplete(() {
          _footnoteDialogOpen = false;
          if (mounted) _readerFocusNode.requestFocus();
        }),
      );
    } else if (_footnoteDialogOpen &&
        _footnote.value?.requestId == note.requestId) {
      _footnote.value = note;
    }
  }

  Future<void> _onReaderReady() async {
    final controller = _webViewController;
    if (controller == null) return;
    try {
      final settings = ref.read(settingsProvider.notifier);
      await Future.wait([
        _progressNotifier.fetchProgress(),
        settings.initialized,
      ]);
      if (!mounted || _webViewController != controller) return;
      final readingSettings = ref.read(settingsProvider);
      await controller.runJavaScript(
        'setStyles(${jsonEncode(readingSettings.buildCss())})',
      );
      await controller.runJavaScript(
        "setPageLayout('${readingSettings.layout == ReadingLayout.twoColumns ? 'two' : 'one'}')",
      );
      final cfi = widget.initialCfi ?? _progressNotifier.lastCfi;
      if (cfi != null) {
        await controller.runJavaScript('goToCfi(${jsonEncode(cfi)})');
      }
      if (!mounted) return;
      await _injectHighlights(controller);
      if (!mounted) return;
      await _injectNotes(controller);
      if (!mounted) return;
      _startReadingTimer();
      setState(() => _isLoading = false);
    } catch (error) {
      _setLoadError('No se pudo preparar el lector: $error');
    }
  }

  Future<void> _onSelectionAction(String message) async {
    if (!mounted) return;
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final text = data['text'] as String?;
      final cfi = data['cfiRange'] as String?;
      if (text == null || text.trim().isEmpty) return;
      switch (data['action']) {
        case 'highlight':
          if (cfi != null && cfi.isNotEmpty) {
            await _chooseHighlightColor(cfi, text);
          }
        case 'note':
          if (cfi != null && cfi.isNotEmpty) await _createNote(cfi, text);
        case 'claude':
          _showClaudeChat(text);
        case 'translate':
          _showTranslation(text);
        case 'vocablingo':
          await _saveToVocablingo(text);
      }
    } catch (error) {
      _showMessage('No se pudo completar la acción: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _setLoadError(String error) {
    debugPrint('Reader error: $error');
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _loadError = error;
    });
  }

  Future<void> _saveToVocablingo(String text) async {
    await saveToVocablingo(
      context,
      service: ref.read(vocablingoServiceProvider),
      selection: text,
      email: Supabase.instance.client.auth.currentUser?.email,
    );
  }

  Future<void> _chooseHighlightColor(String cfiRange, String text) async {
    final color = await showHighlightTypePicker(context);
    if (color != null && mounted) {
      await _addHighlight(cfiRange, text, color.value);
    }
  }

  Future<void> _addHighlight(String cfiRange, String text, String color) async {
    try {
      await ref
          .read(bookHighlightsProvider(widget.bookId).notifier)
          .addHighlight(cfiRange, text, color: color);
      if (mounted) {
        await _webViewController?.runJavaScript(
          'renderHighlights(${jsonEncode([
            {'cfi_range': cfiRange, 'color': color},
          ])})',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Highlight guardado'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (error) {
      _showMessage('No se pudo guardar el highlight: $error');
    }
  }

  Future<void> _injectHighlights(ReaderWebView controller) async {
    final notifier = ref.read(bookHighlightsProvider(widget.bookId).notifier);
    await notifier.fetchHighlights();
    if (!mounted || _webViewController != controller) return;
    final highlights = ref
        .read(bookHighlightsProvider(widget.bookId))
        .highlights;
    if (highlights.isNotEmpty) {
      final json = highlights
          .map((h) => {'cfi_range': h.cfiRange, 'color': h.color})
          .toList();
      await controller.runJavaScript('renderHighlights(${jsonEncode(json)})');
    }
  }

  Future<void> _createNote(String cfiRange, String selectedText) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => NoteEditorSheet(
        selectedText: selectedText,
        onSave: (content, color) async {
          final note = await ref
              .read(bookNotesProvider(widget.bookId).notifier)
              .addNote(
                cfiRange: cfiRange,
                content: content,
                selectedText: selectedText,
                color: color,
              );
          await _webViewController?.runJavaScript(
            'renderNotes(${jsonEncode([
              {'id': note.id, 'cfi_range': note.cfiRange, 'color': note.color},
            ])})',
          );
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Nota guardada')));
          }
        },
      ),
    );
  }

  Future<void> _injectNotes(ReaderWebView controller) async {
    final notifier = ref.read(bookNotesProvider(widget.bookId).notifier);
    await notifier.fetchNotes();
    if (!mounted || _webViewController != controller) return;
    final notes = ref.read(bookNotesProvider(widget.bookId)).notes;
    if (notes.isEmpty) return;
    await controller.runJavaScript(
      'renderNotes(${jsonEncode(notes.map((note) => {'id': note.id, 'cfi_range': note.cfiRange, 'color': note.color}).toList())})',
    );
  }

  void _openNote(String noteId) {
    final notes = ref.read(bookNotesProvider(widget.bookId)).notes;
    final matches = notes.where((note) => note.id == noteId);
    if (matches.isEmpty) return;
    final note = matches.first;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => NoteEditorSheet(
        note: note,
        onSave: (content, color) async {
          await ref
              .read(bookNotesProvider(widget.bookId).notifier)
              .updateNote(note.id, content: content, color: color);
          await _webViewController?.runJavaScript(
            'rendition.annotations.remove(${jsonEncode(note.cfiRange)}, "underline"); renderNotes(${jsonEncode([
              {'id': note.id, 'cfi_range': note.cfiRange, 'color': color},
            ])})',
          );
        },
        onDelete: () async {
          await ref
              .read(bookNotesProvider(widget.bookId).notifier)
              .deleteNote(note.id);
          await _webViewController?.runJavaScript(
            'rendition.annotations.remove(${jsonEncode(note.cfiRange)}, "underline")',
          );
        },
      ),
    );
  }

  void _showClaudeChat(String? selectedText) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => ClaudeChatSheet(
          bookId: widget.bookId,
          selectedText: selectedText,
          readingContext: _claudeReadingContext,
        ),
      ),
    );
  }

  String get _claudeReadingContext {
    final chapter = _chapterLabelForHref(_currentHref);
    final progress = _progress.toStringAsFixed(0);
    return chapter == null
        ? 'approximately $progress% of the book'
        : 'chapter "$chapter", approximately $progress% of the book';
  }

  String? _chapterLabelForHref(String? href) {
    if (href == null || href.isEmpty) return null;
    final normalizedHref = href.split('#').first;
    TocItem? match;

    void visit(List<TocItem> items) {
      for (final item in items) {
        if (item.href.split('#').first == normalizedHref) {
          match = item;
        }
        visit(item.children);
      }
    }

    visit(_tocItems);
    return match?.label.isNotEmpty == true ? match!.label : null;
  }

  void _showTranslation(String selectedText) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) =>
            TranslationSheet(selectedText: selectedText),
      ),
    );
  }

  void _showToc() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) => TocDrawer(
          chapters: _tocItems,
          currentCfi: _currentCfi,
          onChapterSelected: (target) {
            _webViewController?.runJavaScript('goTo(${jsonEncode(target)})');
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _toggleAppBar() {
    if (!mounted) return;
    setState(() => _showChrome = !_showChrome);
  }

  void _saveProgress() {
    ref.read(progressProvider(widget.bookId).notifier).flushProgress();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Progress saved'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _showSettings() {
    final controller = _webViewController;
    if (controller == null) return;

    final width = MediaQuery.of(context).size.width;

    if (width >= 600) {
      showModalBottomSheet(
        context: context,
        builder: (ctx) => SizedBox(
          width: 400,
          child: SettingsPanel(
            onStartAudio: Platform.isWindows && !_isLoading
                ? () {
                    Navigator.pop(ctx);
                    _startAudioRucio();
                  }
                : null,
            onCssChanged: (css) {
              controller.runJavaScript('setStyles(${jsonEncode(css)})');
            },
            onLayoutChanged: (layout) {
              controller.runJavaScript(
                "setPageLayout('${layout == ReadingLayout.twoColumns ? 'two' : 'one'}')",
              );
            },
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollController) => SettingsPanel(
            onCssChanged: (css) {
              controller.runJavaScript('setStyles(${jsonEncode(css)})');
            },
            onLayoutChanged: (layout) {
              controller.runJavaScript(
                "setPageLayout('${layout == ReadingLayout.twoColumns ? 'two' : 'one'}')",
              );
            },
          ),
        ),
      );
    }
  }

  Future<AudioPage?> _requestAudioPage(String? cfi) async {
    final controller = _webViewController;
    if (!mounted || controller == null) {
      throw const AudioRucioException('El lector se ha cerrado.');
    }
    final id = ++_audioRequestId;
    final completer = Completer<AudioPage?>();
    _audioRequests[id] = completer;
    try {
      final response = completer.future.timeout(const Duration(seconds: 20));
      unawaited(
        controller
            .runJavaScript('requestAudioPage($id, ${jsonEncode(cfi)})')
            .catchError((Object error) {
              if (!completer.isCompleted) {
                completer.completeError(
                  const AudioRucioException(
                    'No se pudo leer el texto del libro.',
                  ),
                );
              }
            }),
      );
      return await response;
    } finally {
      _audioRequests.remove(id);
    }
  }

  void _startAudioRucio() {
    if (_isLoading || _webViewController == null || _audioSession != null) {
      return;
    }
    if (_showSearch) _closeSearch();
    final book = _readerContent?.book;
    _audioReaderSize = _readerViewportKey.currentContext?.size;
    setState(() {
      _audioSession = AudioSession(
        userId: book?.userId ?? 'local',
        bookId: widget.bookId,
        initialCfi:
            _currentCfi ?? widget.initialCfi ?? _progressNotifier.lastCfi,
        book: book,
        readerCfi: () => _currentCfi,
        loadPage: _requestAudioPage,
        onPageChanged: (page) async {
          if (mounted) {
            await _webViewController?.runJavaScript(
              'goToCfi(${jsonEncode(page.startCfi)})',
            );
          }
        },
      );
    });
  }

  void _toggleSearch() {
    if (_showSearch) {
      _closeSearch();
      return;
    }
    setState(() => _showSearch = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showSearch) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    _searchFocusNode.unfocus();
    _searchPanelKey.currentState?.clear();
    setState(() {
      _showSearch = false;
      _searchQuery = '';
      _searchResults.clear();
    });
  }

  void _onSearchChanged(String query) {
    _searchQuery = query;
    if (query.trim().length < 2) {
      setState(() => _searchResults.clear());
      _searchPanelKey.currentState?.updateResults(const []);
      return;
    }
    _webViewController?.runJavaScript('searchBook(${jsonEncode(query)})');
  }

  void _onSearchResultTap(SearchResult result) {
    final target = result.cfi.isNotEmpty ? result.cfi : result.href;
    _webViewController?.runJavaScript(
      'goToSearchResult(${jsonEncode(target)})',
    );
    setState(() {
      _showSearch = false;
    });
    _searchFocusNode.unfocus();
  }

  void _startReadingTimer() {
    if (_readingTimer != null) return;
    _readingStartedAt = DateTime.now();
    _readingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _readingStartedAt == null) return;
      setState(() {
        _sessionReadingTime = DateTime.now().difference(_readingStartedAt!);
      });
    });
  }

  String get _readingTimeLabel {
    final minutes = _sessionReadingTime.inMinutes;
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${minutes % 60} min';
  }

  @override
  void dispose() {
    for (final request in _audioRequests.values) {
      if (!request.isCompleted) request.complete(null);
    }
    _audioRequests.clear();
    unawaited(_progressNotifier.flushProgress());
    unawaited(_readerContent?.dispose());
    unawaited(_messageSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_webViewController?.dispose());
    _readingTimer?.cancel();
    _searchFocusNode.dispose();
    _readerFocusNode.dispose();
    _footnote.dispose();
    if (Platform.isAndroid) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;
    return Focus(
      focusNode: _readerFocusNode,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (_showSearch || _audioSession != null || event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          unawaited(_webViewController?.runJavaScript('prevPage()'));
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          unawaited(_webViewController?.runJavaScript('nextPage()'));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: _showChrome && _audioSession == null
            ? AppBar(
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(28),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Text(
                          '${_progress.toStringAsFixed(0)}% leído',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(width: 12),
                        Text('Sesión: $_readingTimeLabel'),
                      ],
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.home_outlined),
                    tooltip: 'Biblioteca',
                    onPressed: () => context.go('/'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.save_outlined),
                    tooltip: 'Guardar progreso',
                    onPressed: _saveProgress,
                  ),
                  PopupMenuButton<_ReaderTool>(
                    tooltip: 'Herramientas de lectura',
                    icon: const Icon(Icons.handyman_outlined),
                    onSelected: (tool) {
                      switch (tool) {
                        case _ReaderTool.search:
                          _toggleSearch();
                        case _ReaderTool.claude:
                          _showClaudeChat(null);
                        case _ReaderTool.toc:
                          _showToc();
                        case _ReaderTool.settings:
                          _showSettings();
                        case _ReaderTool.audio:
                          _startAudioRucio();
                      }
                    },
                    itemBuilder: (context) => [
                      if (Platform.isWindows && !_isLoading)
                        const PopupMenuItem(
                          value: _ReaderTool.audio,
                          child: ListTile(
                            leading: Icon(Icons.headphones_outlined),
                            title: Text('Iniciar Audiorucio'),
                          ),
                        ),
                      const PopupMenuItem(
                        value: _ReaderTool.search,
                        child: ListTile(
                          leading: Icon(Icons.search),
                          title: Text('Buscar en el libro'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _ReaderTool.claude,
                        child: ListTile(
                          leading: Icon(Icons.auto_awesome_outlined),
                          title: Text('Historial de Claude'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _ReaderTool.toc,
                        child: ListTile(
                          leading: Icon(Icons.list),
                          title: Text('Índice'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _ReaderTool.settings,
                        child: ListTile(
                          leading: Icon(Icons.settings),
                          title: Text('Ajustes de lectura'),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : null,
        body: Stack(
          key: _readerViewportKey,
          fit: StackFit.expand,
          children: [
            if (_loadError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_loadError!, textAlign: TextAlign.center),
                ),
              )
            else if (_webViewController != null)
              Positioned(
                left: 0,
                top: 0,
                right: _audioReaderSize == null ? 0 : null,
                bottom: _audioReaderSize == null ? 0 : null,
                width: _audioReaderSize?.width,
                height: _audioReaderSize?.height,
                child: _webViewController!.buildView(),
              )
            else
              const Center(child: CircularProgressIndicator()),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(2),
                ),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 3,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: IgnorePointer(
                ignoring: !_showSearch,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  offset: _showSearch ? Offset.zero : const Offset(-1.1, 0),
                  child: SizedBox(
                    width: isMobile ? screenWidth * 0.92 : 400,
                    child: Material(
                      color: const Color(0xFF1A1827),
                      elevation: 12,
                      child: SearchPanel(
                        key: _searchPanelKey,
                        initialQuery: _searchQuery,
                        focusNode: _searchFocusNode,
                        onSearch: _onSearchChanged,
                        onResultTap: _onSearchResultTap,
                        onClose: _toggleSearch,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_audioSession != null)
              Positioned.fill(
                child: AudioRucioPlayer(
                  session: _audioSession!,
                  onExit: () {
                    unawaited(
                      _webViewController!.runJavaScript('closeAudioReader()'),
                    );
                    setState(() {
                      _audioSession = null;
                      _audioReaderSize = null;
                    });
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _ReaderTool { search, claude, toc, settings, audio }
