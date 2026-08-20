import 'package:flutter/material.dart';

class TocItem {
  final String label;
  final String cfi;
  final String href;
  final List<TocItem> children;

  const TocItem({
    required this.label,
    required this.cfi,
    this.href = '',
    this.children = const [],
  });

  factory TocItem.fromJson(Map<String, dynamic> json) {
    return TocItem(
      label: json['label'] as String? ?? '',
      cfi: json['cfi'] as String? ?? json['href'] as String? ?? '',
      href: json['href'] as String? ?? '',
      children:
          (json['subitems'] as List<dynamic>?)
              ?.map((e) => TocItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class TocDrawer extends StatelessWidget {
  final List<TocItem> chapters;
  final String? currentCfi;
  final void Function(String cfi) onChapterSelected;

  const TocDrawer({
    super.key,
    required this.chapters,
    this.currentCfi,
    required this.onChapterSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        return _TocListTile(
          item: chapter,
          depth: 0,
          isActive: _isActive(chapter),
          onChapterSelected: onChapterSelected,
        );
      },
    );
  }

  bool _isActive(TocItem item) {
    if (currentCfi == null) return false;
    return currentCfi!.startsWith(item.cfi);
  }
}

class _TocListTile extends StatelessWidget {
  final TocItem item;
  final int depth;
  final bool isActive;
  final ValueChanged<String> onChapterSelected;

  const _TocListTile({
    required this.item,
    required this.depth,
    required this.isActive,
    required this.onChapterSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(left: 16.0 + depth * 16.0, right: 16),
          title: Text(
            item.label,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 14 - depth * 1.0,
              color: isActive ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          onTap: () => onChapterSelected(item.cfi),
        ),
        ...item.children.map(
          (child) => _TocListTile(
            item: child,
            depth: depth + 1,
            isActive: isActive,
            onChapterSelected: onChapterSelected,
          ),
        ),
      ],
    );
  }
}
