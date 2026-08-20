import 'package:flutter/material.dart';

import '../models/reading_note.dart';

class NoteEditorSheet extends StatefulWidget {
  const NoteEditorSheet({
    super.key,
    this.note,
    this.selectedText,
    required this.onSave,
    this.onDelete,
  });

  final ReadingNote? note;
  final String? selectedText;
  final Future<void> Function(String content, String color) onSave;
  final Future<void> Function()? onDelete;

  @override
  State<NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<NoteEditorSheet> {
  static const _colors = ['#F2A65A', '#FACC15', '#F87171', '#60A5FA', '#A78BFA'];
  late final TextEditingController _controller;
  late String _color;
  var _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.note?.content ?? '');
    _color = widget.note?.color ?? _colors.first;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await widget.onSave(content, _color);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.onDelete == null) return;
    setState(() => _isSaving = true);
    try {
      await widget.onDelete!();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = widget.note?.selectedText ?? widget.selectedText;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.note == null ? 'Nueva nota' : 'Editar nota',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (quote != null && quote.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF252336),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('“${quote.trim()}”'),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: widget.note == null,
              minLines: 3,
              maxLines: 7,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Escribe tu nota…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              children: _colors
                  .map(
                    (color) => ChoiceChip(
                      label: const SizedBox(width: 16, height: 16),
                      selected: color == _color,
                      selectedColor: _colorFromHex(color),
                      backgroundColor: _colorFromHex(color),
                      onSelected: (_) => setState(() => _color = color),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (widget.onDelete != null)
                  IconButton(
                    tooltip: 'Eliminar nota',
                    color: const Color(0xFFFF9E9E),
                    onPressed: _isSaving ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _colorFromHex(String value) {
    return Color(int.parse('FF${value.replaceFirst('#', '')}', radix: 16));
  }
}
