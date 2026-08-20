import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/highlight.dart';
import '../providers/highlights_provider.dart';

class HighlightsScreen extends ConsumerStatefulWidget {
  const HighlightsScreen({super.key});

  @override
  ConsumerState<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends ConsumerState<HighlightsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(allHighlightsProvider.notifier).fetchHighlightsWithBooks();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(allHighlightsProvider);
    final highlights = _filteredHighlights(state.highlights);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Highlights'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver a la biblioteca',
          onPressed: () => context.go('/'),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search highlights...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
        ),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : highlights.isEmpty
          ? const Center(child: Text('No highlights yet.'))
          : RefreshIndicator(
              onRefresh: () => ref
                  .read(allHighlightsProvider.notifier)
                  .fetchHighlightsWithBooks(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                itemCount: highlights.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final highlight = highlights[index];
                  return Dismissible(
                    key: Key(highlight.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF87171),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Color(0xFF0F0E17),
                      ),
                    ),
                    onDismissed: (_) {
                      ref
                          .read(allHighlightsProvider.notifier)
                          .deleteHighlight(highlight.id);
                    },
                    child: _HighlightCard(
                      highlight: highlight,
                      onTap: () => _openHighlight(highlight),
                      onColorTap: () => _changeHighlightColor(highlight),
                    ),
                  );
                },
              ),
            ),
    );
  }

  List<Highlight> _filteredHighlights(List<Highlight> highlights) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return highlights;
    return highlights
        .where(
          (highlight) =>
              highlight.text.toLowerCase().contains(query) ||
              (highlight.note?.toLowerCase().contains(query) ?? false) ||
              (highlight.bookTitle?.toLowerCase().contains(query) ?? false),
        )
        .toList();
  }

  void _openHighlight(Highlight highlight) {
    if (highlight.bookIsArchived) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El EPUB fue eliminado para liberar espacio.'),
        ),
      );
      return;
    }
    context.go(
      '/reader/${highlight.bookId}?cfi=${Uri.encodeComponent(highlight.cfiRange)}',
    );
  }

  Future<void> _changeHighlightColor(Highlight highlight) async {
    final selected = await showModalBottomSheet<HighlightColorOption>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cambiar tipo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ...HighlightColorOption.values.map(
                (option) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: _colorFromHex(option.value),
                  ),
                  title: Text(option.label),
                  subtitle: Text(option.description),
                  trailing:
                      option.value.toLowerCase() ==
                          highlight.color.toLowerCase()
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, option),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null ||
        selected.value.toLowerCase() == highlight.color.toLowerCase()) {
      return;
    }

    try {
      await ref
          .read(allHighlightsProvider.notifier)
          .updateHighlightColor(highlight.id, selected.value);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cambiar el color: $error')),
      );
    }
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.highlight,
    required this.onTap,
    required this.onColorTap,
  });

  final Highlight highlight;
  final VoidCallback onTap;
  final VoidCallback onColorTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: const Color(0xFF1A1827),
      borderRadius: BorderRadius.circular(20),
      child: _TwoSecondPress(
        onTap: onTap,
        onTriggered: onColorTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: 'Mantén pulsado 2 segundos para cambiar el tipo.',
                child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 5,
                          decoration: BoxDecoration(
                            color: _colorFromHex(highlight.color),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          HighlightColorOption.fromValue(highlight.color).label,
                          style: textTheme.labelMedium?.copyWith(
                            color: const Color(0xFFB7B0C6),
                          ),
                        ),
                      ],
                    ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '"${highlight.text}"',
                style: textTheme.titleMedium?.copyWith(height: 1.55),
              ),
              if (highlight.note != null &&
                  highlight.note!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  highlight.note!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFB7B0C6),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              const Divider(height: 1, color: Color(0xFF252336)),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.menu_book_outlined,
                    size: 18,
                    color: Color(0xFFF2A65A),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      highlight.bookTitle ?? 'Book unavailable',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (highlight.bookAuthor != null &&
                  highlight.bookAuthor!.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.only(left: 26),
                  child: Text(
                    highlight.bookAuthor!,
                    style: textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF7C748E),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                _formatDate(highlight.createdAt),
                style: textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF7C748E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _colorFromHex(String value) {
    final hex = value.replaceFirst('#', '');
    return Color(int.tryParse('FF$hex', radix: 16) ?? 0xFFF2A65A);
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

Color _colorFromHex(String value) {
  final hex = value.replaceFirst('#', '');
  return Color(int.tryParse('FF$hex', radix: 16) ?? 0xFFF2A65A);
}

class _TwoSecondPress extends StatefulWidget {
  const _TwoSecondPress({
    required this.onTap,
    required this.onTriggered,
    required this.child,
  });

  final VoidCallback onTap;
  final VoidCallback onTriggered;
  final Widget child;

  @override
  State<_TwoSecondPress> createState() => _TwoSecondPressState();
}

class _TwoSecondPressState extends State<_TwoSecondPress> {
  Timer? _timer;
  var _triggered = false;

  void _startTimer(TapDownDetails details) {
    _timer?.cancel();
    _triggered = false;
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        _triggered = true;
        widget.onTriggered();
      }
    });
  }

  void _cancelTimer([Object? _]) {
    _timer?.cancel();
    _timer = null;
  }

  void _handleTap() {
    if (!_triggered) {
      widget.onTap();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      onTapDown: _startTimer,
      onTapUp: _cancelTimer,
      onTapCancel: _cancelTimer,
      child: widget.child,
    );
  }
}
