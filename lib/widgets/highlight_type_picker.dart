import 'package:flutter/material.dart';

import '../models/highlight.dart';

Future<HighlightColorOption?> showHighlightTypePicker(BuildContext context) {
  return showModalBottomSheet<HighlightColorOption>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _HighlightTypePicker(
      onSelected: (option) => Navigator.pop(sheetContext, option),
    ),
  );
}

class _HighlightTypePicker extends StatelessWidget {
  const _HighlightTypePicker({required this.onSelected});

  final ValueChanged<HighlightColorOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
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
              const Text('Elige el significado de esta selección.'),
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
      ),
    );
  }
}

Color _colorFromHex(String value) {
  final hex = value.replaceFirst('#', '');
  return Color(int.tryParse('FF$hex', radix: 16) ?? 0xFFF2A65A);
}
