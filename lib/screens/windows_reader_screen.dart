import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_windows/webview_windows.dart';

import '../config/supabase_client_provider.dart';
import '../providers/highlights_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/claude_chat_sheet.dart';
import '../widgets/note_editor_sheet.dart';
import '../widgets/search_panel.dart';
import '../widgets/settings_panel.dart';
import '../widgets/toc_drawer.dart';

class WindowsReaderScreen extends ConsumerStatefulWidget {
  const WindowsReaderScreen({
    super.key,
    required this.bookId,
    this.initialCfi,
  });

  final String bookId;
  final String? initialCfi;

  @override
  ConsumerState<WindowsReaderScreen> createState() =>
      _WindowsReaderScreenState();
}

class _WindowsReaderScreenState extends ConsumerState<WindowsReaderScreen> {
  WebviewController? _controller;
  late final ProgressNotifier _progressNotifier;
  StreamSubscription<dynamic>? _messageSubscription;
  Timer? _readingTimer;
  DateTime? _readingStartedAt;
  Duration _sessionReadingTime = Duration.zero;
  double _progress = 0;
  String? _currentCfi;
  String? _currentHref;
  List<TocItem> _tocItems = [];
  bool _showSearch = false;
  String _searchQuery = '';
  final List<SearchResult> _searchResults = [];
  final GlobalKey<SearchPanelState> _searchPanelKey = GlobalKey();
  final FocusNode _searchFocusNode = FocusNode();
  String? _error;
  var _isLoading = true;

  @override
  void initState() {
    super.initState();
    _progressNotifier = ref.read(progressProvider(widget.bookId).notifier);
    _loadBook();
  }

  Future<void> _loadBook() async {
    try {
      if (await WebviewController.getWebViewVersion() == null) {
        throw StateError(
          'Microsoft Edge WebView2 Runtime is required to read on Windows.',
        );
      }
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw StateError('Your session has expired.');

      final db = ref.read(supabaseClientProvider);
      final book = await db
          .from('books')
          .select()
          .eq('id', widget.bookId)
          .eq('user_id', userId)
          .single();
      final filePath = book['file_path'] as String?;
      if (filePath == null) throw StateError('This EPUB is no longer available.');

      final signedUrl = await Supabase.instance.client.storage
          .from('libros')
          .createSignedUrl(filePath, 3600);
      final response = await Dio().get<List<int>>(
        signedUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final epubBytes = response.data;
      if (epubBytes == null || epubBytes.isEmpty) {
        throw StateError('The downloaded EPUB file is empty.');
      }

      final html = await rootBundle.loadString('assets/reader.html');
      final jsZip = await rootBundle.loadString('assets/epubjs/jszip.min.js');
      final epubJs = await rootBundle.loadString('assets/epubjs/epub.min.js');
      final content = html
          .replaceFirst('{{{JSZIP_SOURCE}}}', jsZip)
          .replaceFirst('{{{EPUBJS_SOURCE}}}', epubJs)
          .replaceFirst('{{{EPUB_DATA_JSON}}}', jsonEncode(base64Encode(epubBytes)));

      final controller = WebviewController();
      await controller.initialize();
      _messageSubscription = controller.webMessage.listen(_onWebMessage);
      controller.onLoadError.listen((_) {
        _setError('The reader page could not be loaded.');
      });
      await controller.setBackgroundColor(const Color(0xFF0F0E17));
      _controller = controller;
      await controller.loadStringContent(content);
    } catch (error) {
      _setError('$error');
    }
  }

  void _onWebMessage(dynamic event) {
    if (event is! Map) return;
    final channel = event['channel']?.toString();
    final message = event['message']?.toString() ?? '';
    switch (channel) {
      case 'ReaderReady':
        unawaited(_onReaderReady());
      case 'Relocated':
        final data = jsonDecode(message) as Map<String, dynamic>;
        final cfi = data['cfi'] as String? ?? '';
        final href = data['href'] as String?;
        final percentage = (data['percentage'] as num?)?.toDouble() ?? 0;
        if (mounted) {
          setState(() {
            _currentCfi = cfi;
            _currentHref = href;
            _progress = percentage;
          });
        }
        ref.read(progressProvider(widget.bookId).notifier).saveProgress(cfi, percentage);
      case 'Toc':
        final data = jsonDecode(message) as List<dynamic>;
        if (mounted) {
          setState(() {
            _tocItems = data
                .map((item) => TocItem.fromJson(item as Map<String, dynamic>))
                .toList();
          });
        }
      case 'SearchResults':
        final data = jsonDecode(message) as List<dynamic>;
        final results = data
            .map((item) => SearchResult.fromJson(item as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            _searchResults
              ..clear()
              ..addAll(results);
          });
        }
        _searchPanelKey.currentState?.updateResults(results);
      case 'SelectionAction':
        unawaited(_onSelectionAction(message));
      case 'NoteTapped':
        _openNote(message);
      case 'ReaderError':
        _setError(message);
    }
  }

  Future<void> _onReaderReady() async {
    final controller = _controller;
    if (controller == null) return;
    final progress = ref.read(progressProvider(widget.bookId).notifier);
    await progress.fetchProgress();
    await _runJavaScript('setStyles(${jsonEncode(ref.read(settingsProvider).buildCss())})');
    final layout = ref.read(settingsProvider).layout;
    await _runJavaScript(
      "setPageLayout('${layout == ReadingLayout.twoColumns ? 'two' : 'one'}')",
    );
    final target = widget.initialCfi ?? progress.lastCfi;
    if (target != null) await _runJavaScript('goToCfi(${jsonEncode(target)})');
    await _injectHighlights();
    await _injectNotes();
    _startReadingTimer();
    if (mounted) setState(() => _isLoading = false);
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

  Future<void> _onSelectionAction(String message) async {
    final data = jsonDecode(message) as Map<String, dynamic>;
    final action = data['action'] as String?;
    final text = data['text'] as String?;
    if (text == null || text.trim().isEmpty) return;
    if (action == 'highlight') {
      final cfiRange = data['cfiRange'] as String?;
      if (cfiRange == null) return;
      await ref
          .read(bookHighlightsProvider(widget.bookId).notifier)
          .addHighlight(cfiRange, text, color: '#FACC15');
      await _runJavaScript(
        'renderHighlights(${jsonEncode([{'cfi_range': cfiRange, 'color': '#FACC15'}])})',
      );
      _showMessage('Highlight saved');
    } else if (action == 'note') {
      final cfiRange = data['cfiRange'] as String?;
      if (cfiRange == null) return;
      _createNote(cfiRange, text);
    } else if (action == 'claude') {
      _showClaudeChat(text);
    } else if (action == 'translate') {
      _showMessage('La traducción sin conexión está disponible en Android e iOS.');
    } else if (action == 'vocablingo') {
      _showMessage('Vocablingo está disponible actualmente en móvil.');
    }
  }

  Future<void> _injectHighlights() async {
    await ref.read(bookHighlightsProvider(widget.bookId).notifier).fetchHighlights();
    final highlights = ref.read(bookHighlightsProvider(widget.bookId)).highlights;
    if (highlights.isEmpty) return;
    await _runJavaScript(
      'renderHighlights(${jsonEncode(highlights.map((h) => {'cfi_range': h.cfiRange, 'color': h.color}).toList())})',
    );
  }

  Future<void> _injectNotes() async {
    await ref.read(bookNotesProvider(widget.bookId).notifier).fetchNotes();
    final notes = ref.read(bookNotesProvider(widget.bookId)).notes;
    if (notes.isEmpty) return;
    await _runJavaScript(
      'renderNotes(${jsonEncode(
        notes
            .map((note) => {
                  'id': note.id,
                  'cfi_range': note.cfiRange,
                  'color': note.color,
                })
            .toList(),
      )})',
    );
  }

  void _createNote(String cfiRange, String selectedText) {
    showModalBottomSheet(
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
          await _runJavaScript(
            'renderNotes(${jsonEncode([
              {'id': note.id, 'cfi_range': note.cfiRange, 'color': note.color},
            ])})',
          );
          _showMessage('Nota guardada');
        },
      ),
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
          await _runJavaScript(
            'rendition.annotations.remove(${jsonEncode(note.cfiRange)}, "underline"); renderNotes(${jsonEncode([
              {
                'id': note.id,
                'cfi_range': note.cfiRange,
                'color': color,
              },
            ])})',
          );
        },
        onDelete: () async {
          await ref.read(bookNotesProvider(widget.bookId).notifier).deleteNote(note.id);
          await _runJavaScript(
            'rendition.annotations.remove(${jsonEncode(note.cfiRange)}, "underline")',
          );
        },
      ),
    );
  }

  void _showClaudeChat(String? selectedText) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, _) => ClaudeChatSheet(
          bookId: widget.bookId,
          selectedText: selectedText,
          readingContext: _claudeReadingContext,
        ),
      ),
    );
  }

  void _toggleSearch() {
    if (_showSearch) {
      _closeSearch();
      return;
    }
    setState(() => _showSearch = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showSearch) _searchFocusNode.requestFocus();
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
      _searchPanelKey.currentState?.updateResults(const []);
      return;
    }
    unawaited(_runJavaScript('searchBook(${jsonEncode(query)})'));
  }

  void _onSearchResultTap(SearchResult result) {
    final target = result.cfi.isNotEmpty ? result.cfi : result.href;
    unawaited(_runJavaScript('goToSearchResult(${jsonEncode(target)})'));
    _closeSearch();
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

  Future<void> _runJavaScript(String script) async {
    await _controller?.executeScript(script);
  }

  void _setError(String error) {
    if (!mounted) return;
    setState(() {
      _error = error;
      _isLoading = false;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showToc() {
    showModalBottomSheet(
      context: context,
      builder: (_) => TocDrawer(
        chapters: _tocItems,
        currentCfi: _currentCfi,
        onChapterSelected: (target) {
          unawaited(_runJavaScript('goTo(${jsonEncode(target)})'));
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SizedBox(
        width: 420,
        child: SettingsPanel(
          onCssChanged: (css) => unawaited(_runJavaScript('setStyles(${jsonEncode(css)})')),
          onLayoutChanged: (layout) => unawaited(
            _runJavaScript(
              "setPageLayout('${layout == ReadingLayout.twoColumns ? 'two' : 'one'}')",
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_progressNotifier.flushProgress());
    _readingTimer?.cancel();
    _messageSubscription?.cancel();
    _searchFocusNode.dispose();
    final controller = _controller;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          unawaited(_runJavaScript('prevPage()'));
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowRight) {
          unawaited(_runJavaScript('nextPage()'));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
        child: Scaffold(
          appBar: AppBar(
            title: Text('${_progress.toStringAsFixed(0)}% leído'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(28),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text('Sesión: $_readingTimeLabel'),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Biblioteca',
                icon: const Icon(Icons.home_outlined),
                onPressed: () => context.go('/'),
              ),
              IconButton(
                tooltip: 'Guardar progreso',
                icon: const Icon(Icons.save_outlined),
                onPressed: () => ref
                    .read(progressProvider(widget.bookId).notifier)
                    .flushProgress(),
              ),
              PopupMenuButton<_WindowsReaderTool>(
                tooltip: 'Herramientas de lectura',
                icon: const Icon(Icons.handyman_outlined),
                onSelected: (tool) {
                  switch (tool) {
                    case _WindowsReaderTool.search:
                      _toggleSearch();
                    case _WindowsReaderTool.claude:
                      _showClaudeChat(null);
                    case _WindowsReaderTool.toc:
                      _showToc();
                    case _WindowsReaderTool.settings:
                      _showSettings();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _WindowsReaderTool.search,
                    child: ListTile(
                      leading: Icon(Icons.search),
                      title: Text('Buscar en el libro'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _WindowsReaderTool.claude,
                    child: ListTile(
                      leading: Icon(Icons.auto_awesome_outlined),
                      title: Text('Historial de Claude'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _WindowsReaderTool.toc,
                    child: ListTile(
                      leading: Icon(Icons.list),
                      title: Text('Índice'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _WindowsReaderTool.settings,
                    child: ListTile(
                      leading: Icon(Icons.settings),
                      title: Text('Ajustes de lectura'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        body: Stack(
          children: [
            if (_error != null)
              Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
            else if (_controller != null)
              Webview(_controller!)
            else
              const Center(child: CircularProgressIndicator()),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
            if (_showSearch)
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 420,
                  child: Material(
                    color: const Color(0xFF1A1827),
                    elevation: 12,
                    child: SearchPanel(
                      key: _searchPanelKey,
                      initialQuery: _searchQuery,
                      focusNode: _searchFocusNode,
                      onSearch: _onSearchChanged,
                      onResultTap: _onSearchResultTap,
                      onClose: _closeSearch,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(value: _progress / 100, minHeight: 3),
            ),
          ],
        ),
      ),
    );
  }
}

enum _WindowsReaderTool { search, claude, toc, settings }
