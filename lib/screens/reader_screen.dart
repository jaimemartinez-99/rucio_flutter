import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/supabase_client_provider.dart';
import '../models/highlight.dart';
import '../providers/highlights_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/settings_provider.dart';
import '../services/vocablingo_service.dart';
import '../widgets/claude_chat_sheet.dart';
import '../widgets/note_editor_sheet.dart';
import '../widgets/search_panel.dart';
import '../widgets/settings_panel.dart';
import '../widgets/toc_drawer.dart';
import '../widgets/translation_sheet.dart';
import 'windows_reader_screen.dart';

class ReaderScreen extends StatelessWidget {
  final String bookId;
  final String? initialCfi;

  const ReaderScreen({super.key, required this.bookId, this.initialCfi});

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) {
      return WindowsReaderScreen(bookId: bookId, initialCfi: initialCfi);
    }
    return _MobileReaderScreen(bookId: bookId, initialCfi: initialCfi);
  }
}

class _MobileReaderScreen extends ConsumerStatefulWidget {
  final String bookId;
  final String? initialCfi;

  const _MobileReaderScreen({required this.bookId, this.initialCfi});

  @override
  ConsumerState<_MobileReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<_MobileReaderScreen> {
  WebViewController? _webViewController;
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
  bool _showSearch = false;
  String _searchQuery = '';
  final List<SearchResult> _searchResults = [];
  final GlobalKey<SearchPanelState> _searchPanelKey = GlobalKey();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _progressNotifier = ref.read(progressProvider(widget.bookId).notifier);
    if (Platform.isAndroid) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
    }
    _loadBook();
  }

  Future<void> _loadBook() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        throw StateError('Your session has expired. Please sign in again.');
      }

      final db = ref.read(supabaseClientProvider);

      final bookData = await db
          .from('books')
          .select()
          .eq('id', widget.bookId)
          .eq('user_id', userId)
          .single();

      if (!Platform.isAndroid && !Platform.isIOS) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final signedUrl = await Supabase.instance.client.storage
          .from('libros')
          .createSignedUrl(bookData['file_path'] as String, 3600);
      final epubResponse = await Dio().get<List<int>>(
        signedUrl,
        options: Options(
          responseType: ResponseType.bytes,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final epubBytes = epubResponse.data;
      if (epubBytes == null || epubBytes.isEmpty) {
        throw StateError('The downloaded EPUB file is empty.');
      }

      final htmlContent = await rootBundle.loadString('assets/reader.html');
      final jsZipSource = await rootBundle.loadString(
        'assets/epubjs/jszip.min.js',
      );
      final epubJsSource = await rootBundle.loadString(
        'assets/epubjs/epub.min.js',
      );
      final fullHtml = htmlContent
          .replaceFirst('{{{JSZIP_SOURCE}}}', jsZipSource)
          .replaceFirst('{{{EPUBJS_SOURCE}}}', epubJsSource)
          .replaceFirst(
            '{{{EPUB_DATA_JSON}}}',
            jsonEncode(base64Encode(epubBytes)),
          );

      final controller = WebViewController();
      await controller.enableZoom(true);

      controller.addJavaScriptChannel(
        'Relocated',
        onMessageReceived: (message) {
          final data = jsonDecode(message.message) as Map<String, dynamic>;
          final cfi = data['cfi'] as String?;
          final href = data['href'] as String?;
          final pct = (data['percentage'] as num?)?.toDouble() ?? 0;
          setState(() {
            _currentCfi = cfi;
            _currentHref = href;
            _progress = pct;
          });
          ref
              .read(progressProvider(widget.bookId).notifier)
              .saveProgress(cfi ?? '', pct);
        },
      );

      controller.addJavaScriptChannel(
        'Selection',
        onMessageReceived: (_) => setState(() {}),
      );

      controller.addJavaScriptChannel(
        'SelectionAction',
        onMessageReceived: (message) {
          final data = jsonDecode(message.message) as Map<String, dynamic>;
          final action = data['action'] as String?;
          final cfiRange = data['cfiRange'] as String?;
          final text = data['text'] as String?;
          if (text == null) return;
          switch (action) {
            case 'highlight':
              if (cfiRange != null) _chooseHighlightColor(cfiRange, text);
              break;
            case 'note':
              if (cfiRange != null) _createNote(cfiRange, text);
              break;
            case 'claude':
              _showClaudeChat(text);
              break;
            case 'translate':
              _showTranslation(text);
              break;
            case 'vocablingo':
              _saveToVocablingo(text);
              break;
          }
        },
      );

      controller.addJavaScriptChannel(
        'NoteTapped',
        onMessageReceived: (message) => _openNote(message.message),
      );

      controller.addJavaScriptChannel(
        'Toc',
        onMessageReceived: (message) {
          final List<dynamic> tocJson = jsonDecode(message.message);
          setState(() {
            _tocItems = tocJson
                .map((e) => TocItem.fromJson(e as Map<String, dynamic>))
                .toList();
          });
        },
      );

      controller.addJavaScriptChannel(
        'ToggleUI',
        onMessageReceived: (_) {
          _toggleAppBar();
        },
      );

      controller.addJavaScriptChannel(
        'ReaderReady',
        onMessageReceived: (_) async {
          if (mounted) setState(() => _isLoading = false);
          _startReadingTimer();
          final progress = ref.read(progressProvider(widget.bookId).notifier);
          await progress.fetchProgress();
          final css = ref.read(settingsProvider).buildCss();
          await controller.runJavaScript('setStyles(${jsonEncode(css)})');
          final layout = ref.read(settingsProvider).layout;
          await controller.runJavaScript(
            "setPageLayout('${layout == ReadingLayout.twoColumns ? 'two' : 'one'}')",
          );
          final targetCfi = widget.initialCfi ?? progress.lastCfi;
          if (targetCfi != null) {
            await Future<void>.delayed(const Duration(milliseconds: 150));
            await controller.runJavaScript('goToCfi(${jsonEncode(targetCfi)})');
          }
          await _injectHighlights(controller);
          await _injectNotes(controller);
        },
      );

      controller.addJavaScriptChannel(
        'ReaderError',
        onMessageReceived: (message) {
          _setLoadError(message.message);
        },
      );

      controller.addJavaScriptChannel(
        'SearchResults',
        onMessageReceived: (message) {
          final List<dynamic> jsonList = jsonDecode(message.message);
          final results = jsonList
              .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
              .toList();
          setState(() {
            _searchResults
              ..clear()
              ..addAll(results);
          });
          _searchPanelKey.currentState?.updateResults(results);
        },
      );

      controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      controller.setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              _setLoadError('Reader page failed to load: ${error.description}');
            }
          },
        ),
      );

      _webViewController = controller;

      await controller.loadHtmlString(fullHtml);
    } catch (e) {
      _setLoadError('Failed to load book: $e');
    }
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
    final service = ref.read(vocablingoServiceProvider);
    try {
      if (!await _ensureVocablingoSession(service)) return;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saving to Vocablingo...')));
      final result = await service.saveSelection(text);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        final type = result['type'] == 'word'
            ? 'Word and definition'
            : 'Phrase';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$type saved: ${result['text']}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }

  Future<bool> _ensureVocablingoSession(VocablingoService service) async {
    if (service.isAuthenticated) return true;

    final emailController = TextEditingController(
      text: Supabase.instance.client.auth.currentUser?.email ?? '',
    );
    final passwordController = TextEditingController();
    final credentials = await showDialog<({String email, String password})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign in to Vocablingo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Use your Vocablingo account to save this selection.'),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, (
              email: emailController.text.trim(),
              password: passwordController.text,
            )),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    emailController.dispose();
    passwordController.dispose();
    if (credentials == null) return false;

    try {
      await service.signIn(credentials.email, credentials.password);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vocablingo sign-in failed: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _chooseHighlightColor(String cfiRange, String text) async {
    final color = await showModalBottomSheet<HighlightColorOption>(
      context: context,
      builder: (sheetContext) => _HighlightColorPicker(
        onSelected: (option) => Navigator.pop(sheetContext, option),
      ),
    );
    if (color != null) {
      await _addHighlight(cfiRange, text, color.value);
    }
  }

  Future<void> _addHighlight(String cfiRange, String text, String color) async {
    try {
      await ref
          .read(bookHighlightsProvider(widget.bookId).notifier)
          .addHighlight(cfiRange, text, color: color);
      if (mounted) {
        _webViewController?.runJavaScript(
          'renderHighlights(${jsonEncode([
            {'cfi_range': cfiRange, 'color': color},
          ])})',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Highlight saved'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _injectHighlights(WebViewController controller) async {
    final notifier = ref.read(bookHighlightsProvider(widget.bookId).notifier);
    await notifier.fetchHighlights();
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Nota guardada')),
            );
          }
        },
      ),
    );
  }

  Future<void> _injectNotes(WebViewController controller) async {
    final notifier = ref.read(bookNotesProvider(widget.bookId).notifier);
    await notifier.fetchNotes();
    final notes = ref.read(bookNotesProvider(widget.bookId)).notes;
    if (notes.isEmpty) return;
    await controller.runJavaScript(
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
        builder: (ctx, scrollController) =>
            ClaudeChatSheet(
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
        builder: (context, scrollController) => TranslationSheet(
          selectedText: selectedText,
        ),
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
    setState(() {});
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
    unawaited(_progressNotifier.flushProgress());
    _readingTimer?.cancel();
    _searchFocusNode.dispose();
    if (Platform.isAndroid) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
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
            tooltip: 'Library',
            onPressed: () => context.go('/'),
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save progress',
            onPressed: _saveProgress,
          ),
          PopupMenuButton<_MobileReaderTool>(
            tooltip: 'Herramientas de lectura',
            icon: const Icon(Icons.handyman_outlined),
            onSelected: (tool) {
              switch (tool) {
                case _MobileReaderTool.search:
                  _toggleSearch();
                case _MobileReaderTool.claude:
                  _showClaudeChat(null);
                case _MobileReaderTool.toc:
                  _showToc();
                case _MobileReaderTool.settings:
                  _showSettings();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _MobileReaderTool.search,
                child: ListTile(
                  leading: Icon(Icons.search),
                  title: Text('Buscar en el libro'),
                ),
              ),
              PopupMenuItem(
                value: _MobileReaderTool.claude,
                child: ListTile(
                  leading: Icon(Icons.auto_awesome_outlined),
                  title: Text('Historial de Claude'),
                ),
              ),
              PopupMenuItem(
                value: _MobileReaderTool.toc,
                child: ListTile(
                  leading: Icon(Icons.list),
                  title: Text('Índice'),
                ),
              ),
              PopupMenuItem(
                value: _MobileReaderTool.settings,
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
          if (!Platform.isAndroid && !Platform.isIOS && !_isLoading)
            const Center(
              child: Text(
                'Book reading is only supported\non Android and iOS.',
                textAlign: TextAlign.center,
              ),
            )
          else if (_loadError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_loadError!, textAlign: TextAlign.center),
              ),
            )
          else if (_webViewController != null)
            WebViewWidget(controller: _webViewController!)
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
        ],
      ),
    );
  }
}

enum _MobileReaderTool { search, claude, toc, settings }

class _HighlightColorPicker extends StatelessWidget {
  const _HighlightColorPicker({required this.onSelected});

  final ValueChanged<HighlightColorOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tipo de highlight',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Elige el significado de esta seleccion.'),
            const SizedBox(height: 16),
            ...HighlightColorOption.values.map(
              (option) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _colorFromHex(option.value),
                ),
                title: Text(option.label),
                subtitle: Text(option.description),
                onTap: () => onSelected(option),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _colorFromHex(String value) {
  final hex = value.replaceFirst('#', '');
  return Color(int.tryParse('FF$hex', radix: 16) ?? 0xFFF2A65A);
}
