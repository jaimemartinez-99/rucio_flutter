import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/book.dart';

class BookCard extends StatefulWidget {
  final Book book;
  final double progress;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const BookCard({
    super.key,
    required this.book,
    this.progress = 0,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<BookCard> {
  Uint8List? _coverBytes;

  @override
  void initState() {
    super.initState();
    _decodeCover();
  }

  @override
  void didUpdateWidget(BookCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.coverUrl != widget.book.coverUrl) _decodeCover();
  }

  void _decodeCover() {
    final dataUrl = widget.book.coverUrl;
    if (dataUrl == null) {
      _coverBytes = null;
      return;
    }
    try {
      final encoded = dataUrl.contains(',') ? dataUrl.split(',').last : dataUrl;
      _coverBytes = base64Decode(encoded);
    } catch (_) {
      _coverBytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap ?? () => context.go('/reader/${widget.book.id}'),
        onLongPress: widget.onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _coverBytes != null
                  ? Container(
                      color: const Color(0xFF252336),
                      padding: const EdgeInsets.all(6),
                      child: Image.memory(
                        _coverBytes!,
                        cacheWidth: 600,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            _placeholder(context),
                      ),
                    )
                  : _placeholder(context),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.book.author != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.book.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(150),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: widget.progress.clamp(0, 100) / 100,
                      minHeight: 3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.book_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.onSurface.withAlpha(80),
        ),
      ),
    );
  }
}
