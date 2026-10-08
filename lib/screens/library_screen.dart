import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/book.dart';
import '../providers/app_update_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/book_progresses_provider.dart';
import '../providers/books_provider.dart';
import '../widgets/book_card.dart';
import '../widgets/book_info_dialog.dart';
import '../widgets/app_update_dialog.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  late final TextEditingController _searchController;
  final _scrollController = ScrollController();
  bool _initialFetchDone = false;
  bool _updateDialogOpen = false;

  Future<void> _checkUpdates({bool automatic = false}) async {
    if (!Platform.isAndroid || _updateDialogOpen || !mounted) return;
    final controller = ref.read(appUpdateProvider.notifier);
    if (automatic) {
      if (!await controller.check(automatic: true) ||
          !mounted ||
          _updateDialogOpen) {
        return;
      }
    } else {
      unawaited(controller.check());
    }
    _updateDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => const AppUpdateDialog(),
      );
    } finally {
      _updateDialogOpen = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(booksProvider).searchQuery,
    );
    Future.microtask(() {
      final user = ref.read(authProvider).user;
      if (user != null) {
        _initialFetchDone = true;
        ref.read(booksProvider.notifier).fetchBooks();
        unawaited(_checkUpdates(automatic: true));
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await ref.read(booksProvider.notifier).fetchBooks();
    ref.invalidate(bookProgressesProvider);
  }

  void _onSearchChanged(String query) {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    ref.read(booksProvider.notifier).searchBooks(query);
  }

  Future<void> _manageBook(Book book) async {
    final action = await showModalBottomSheet<_BookAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(book.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Información del libro'),
                  subtitle: const Text(
                    'Autor, páginas y otros datos del EPUB.',
                  ),
                  onTap: () => Navigator.pop(sheetContext, _BookAction.info),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Liberar espacio'),
                  subtitle: const Text(
                    'Elimina el EPUB y conserva los highlights y las notas.',
                  ),
                  onTap: () =>
                      Navigator.pop(sheetContext, _BookAction.removeEpub),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever_outlined,
                    color: Color(0xFFF87171),
                  ),
                  title: const Text('Eliminar definitivamente'),
                  subtitle: const Text(
                    'Borra el libro, los highlights y las notas.',
                  ),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    _BookAction.deletePermanently,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == null) return;
    if (!mounted) return;

    if (action == _BookAction.info) {
      await showDialog<void>(
        context: context,
        builder: (context) => BookInfoDialog(book: book),
      );
      return;
    }

    if (action == _BookAction.deletePermanently) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Eliminar definitivamente'),
          content: Text(
            'Se eliminarán "${book.title}", sus highlights y sus notas. Esta acción no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      final notifier = ref.read(booksProvider.notifier);
      if (action == _BookAction.removeEpub) {
        await notifier.removeEpub(book);
      } else {
        await notifier.deleteBookPermanently(book);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == _BookAction.removeEpub
                ? 'EPUB eliminado. Tus highlights y notas se han conservado.'
                : 'Libro, highlights y notas eliminados.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo completar la acción: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      if (!_initialFetchDone && next.user != null) {
        _initialFetchDone = true;
        ref.read(booksProvider.notifier).fetchBooks();
        unawaited(_checkUpdates(automatic: true));
      }
    });

    final state = ref.watch(booksProvider);
    final filtered = ref.read(booksProvider.notifier).filteredBooks;
    final progressMap = ref.watch(bookProgressesProvider).valueOrNull ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const _RucioWordmark(),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(68),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar por título o autor',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: state.searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        actions: [
          if (Platform.isAndroid)
            PopupMenuButton<String>(
              tooltip: 'Opciones',
              onSelected: (_) => unawaited(_checkUpdates()),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'updates',
                  child: ListTile(
                    leading: Icon(Icons.system_update),
                    title: Text('Buscar actualizaciones'),
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.format_paint),
            tooltip: 'Highlights',
            onPressed: () => context.go('/highlights'),
          ),
          IconButton(
            icon: const Icon(Icons.sticky_note_2_outlined),
            tooltip: 'Notas',
            onPressed: () => context.go('/notes'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).signOut(),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : filtered.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.library_books_outlined,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withAlpha(80),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.books.isEmpty
                        ? 'No books yet. Tap + to upload.'
                        : 'No hay libros que coincidan con tu búsqueda.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _onRefresh,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 900
                      ? 4
                      : constraints.maxWidth > 600
                      ? 3
                      : 2;
                  return GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: 0.6,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final book = filtered[index];
                      return BookCard(
                        book: book,
                        progress: progressMap[book.id] ?? 0,
                        onLongPress: () => _manageBook(book),
                      );
                    },
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          try {
            await ref.read(booksProvider.notifier).uploadEpub();
          } catch (error) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not upload EPUB: $error')),
            );
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

enum _BookAction { info, removeEpub, deletePermanently }

class _RucioWordmark extends StatelessWidget {
  const _RucioWordmark();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Rucio',
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontFamily: 'serif',
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.1,
        color: const Color(0xFFF2A65A),
      ),
    );
  }
}
