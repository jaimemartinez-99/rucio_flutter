import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/book.dart';

class BookCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => context.go('/reader/${book.id}'),
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: book.coverUrl != null
                  ? Container(
                      color: const Color(0xFF252336),
                      padding: const EdgeInsets.all(6),
                      child: Image.memory(
                        _decodeBase64(book.coverUrl!),
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
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (book.author != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      book.author!,
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
                      value: progress / 100,
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

  Uint8List _decodeBase64(String dataUrl) {
    final base64 = dataUrl.contains(',') ? dataUrl.split(',').last : dataUrl;
    return base64Decode(base64);
  }
}
