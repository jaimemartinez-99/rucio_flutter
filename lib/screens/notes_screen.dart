import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/reading_note.dart';
import '../providers/notes_provider.dart';
import '../widgets/note_editor_sheet.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(allNotesProvider.notifier).fetchNotes(includeBooks: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(allNotesProvider);
    final notes = state.notes.where(_matchesQuery).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notas'),
        leading: IconButton(
          tooltip: 'Volver a la biblioteca',
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Buscar en tus notas',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
        ),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : notes.isEmpty
          ? const Center(child: Text('Aún no tienes notas.'))
          : RefreshIndicator(
              onRefresh: () => ref
                  .read(allNotesProvider.notifier)
                  .fetchNotes(includeBooks: true),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                itemCount: notes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final note = notes[index];
                  return Dismissible(
                    key: Key(note.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => _confirmDelete(note),
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF87171),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.delete_outline),
                    ),
                    onDismissed: (_) => ref
                        .read(allNotesProvider.notifier)
                        .deleteNote(note.id),
                    child: _NoteCard(
                      note: note,
                      onTap: () => _openNote(note),
                      onEdit: () => _editNote(note),
                    ),
                  );
                },
              ),
            ),
    );
  }

  bool _matchesQuery(ReadingNote note) {
    final query = _query.trim().toLowerCase();
    return query.isEmpty ||
        note.content.toLowerCase().contains(query) ||
        (note.selectedText?.toLowerCase().contains(query) ?? false) ||
        (note.bookTitle?.toLowerCase().contains(query) ?? false);
  }

  Future<bool> _confirmDelete(ReadingNote note) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Eliminar nota'),
            content: const Text('Esta acción no se puede deshacer.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _openNote(ReadingNote note) {
    if (note.bookIsArchived) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El EPUB ya no está disponible.')),
      );
      return;
    }
    context.go(
      '/reader/${note.bookId}?cfi=${Uri.encodeComponent(note.cfiRange)}',
    );
  }

  void _editNote(ReadingNote note) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => NoteEditorSheet(
        note: note,
        onSave: (content, color) => ref
            .read(allNotesProvider.notifier)
            .updateNote(note.id, content: content, color: color),
        onDelete: () => ref.read(allNotesProvider.notifier).deleteNote(note.id),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.onTap,
    required this.onEdit,
  });

  final ReadingNote note;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1827),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 5,
                height: 84,
                decoration: BoxDecoration(
                  color: _colorFromHex(note.color),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (note.selectedText?.trim().isNotEmpty ?? false)
                      Text(
                        '“${note.selectedText!.trim()}”',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFB7B0C6),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    if (note.selectedText?.trim().isNotEmpty ?? false)
                      const SizedBox(height: 8),
                    Text(note.content, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),
                    Text(
                      note.bookTitle ?? 'Libro no disponible',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFF2A65A),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Editar nota',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _colorFromHex(String value) {
    return Color(int.tryParse('FF${value.replaceFirst('#', '')}', radix: 16) ?? 0xFFF2A65A);
  }
}
