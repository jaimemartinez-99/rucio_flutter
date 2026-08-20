import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/book.dart';
import '../providers/auth_provider.dart';
import '../providers/book_progresses_provider.dart';
import '../providers/books_provider.dart';
import '../widgets/book_card.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _isSearching = false;
  final _searchController = TextEditingController();
  bool _initialFetchDone = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final user = ref.read(authProvider).user;
      if (user != null) {
        _initialFetchDone = true;
        ref.read(booksProvider.notifier).fetchBooks();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await ref.read(booksProvider.notifier).fetchBooks();
    ref.invalidate(bookProgressesProvider);
  }

  void _onSearchChanged(String query) {
    ref.read(booksProvider.notifier).searchBooks(query);
  }

  Future<void> _manageBook(Book book) async {
    final action = await showModalBottomSheet<_BookRemovalAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(book.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Liberar espacio'),
                subtitle: const Text(
                  'Elimina el EPUB y conserva los highlights y las notas.',
                ),
                onTap: () => Navigator.pop(
                  sheetContext,
                  _BookRemovalAction.removeEpub,
                ),
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
                  _BookRemovalAction.deletePermanently,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null) return;
    if (!mounted) return;

    if (action == _BookRemovalAction.deletePermanently) {
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
      if (action == _BookRemovalAction.removeEpub) {
        await notifier.removeEpub(book);
      } else {
        await notifier.deleteBookPermanently(book);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == _BookRemovalAction.removeEpub
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
      }
    });

    final state = ref.watch(booksProvider);
    final filtered = ref.read(booksProvider.notifier).filteredBooks;
    final progressMap = ref.watch(bookProgressesProvider).valueOrNull ?? {};

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Search books...',
                  border: InputBorder.none,
                ),
              )
            : const _RucioWordmark(),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  ref.read(booksProvider.notifier).searchBooks('');
                }
              });
            },
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
                        : 'No books match your search.',
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

enum _BookRemovalAction { removeEpub, deletePermanently }

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
