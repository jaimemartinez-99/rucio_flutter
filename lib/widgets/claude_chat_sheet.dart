import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/claude_provider.dart';

class ClaudeChatSheet extends ConsumerStatefulWidget {
  final String bookId;
  final String? selectedText;
  final String? readingContext;

  const ClaudeChatSheet({
    super.key,
    required this.bookId,
    this.selectedText,
    this.readingContext,
  });

  @override
  ConsumerState<ClaudeChatSheet> createState() => _ClaudeChatSheetState();
}

class _ClaudeChatSheetState extends ConsumerState<ClaudeChatSheet> {
  final _questionController = TextEditingController();
  final _scrollController = ScrollController();
  String? _error;
  var _isShowingHistory = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(claudeProvider(widget.bookId).notifier).clearVisibleMessages();
    });
  }

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;

    _questionController.clear();
    setState(() => _error = null);

    try {
      await ref
          .read(claudeProvider(widget.bookId).notifier)
          .askQuestion(
            widget.selectedText,
            question,
            readingContext: widget.readingContext,
          );
      _scrollToBottom();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _showHistory() async {
    setState(() => _isShowingHistory = true);
    await ref.read(claudeProvider(widget.bookId).notifier).fetchHistory();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(claudeProvider(widget.bookId));

    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFF7C748E),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFF10B981)),
              const SizedBox(width: 10),
              Text('Ask Claude', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              TextButton.icon(
                onPressed: _isShowingHistory || state.isLoading
                    ? null
                    : _showHistory,
                icon: const Icon(Icons.history_outlined, size: 18),
                label: const Text('Mostrar historial'),
              ),
            ],
          ),
        ),
        if (widget.selectedText != null &&
            widget.selectedText!.trim().isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF252336),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Using selected text: ${widget.selectedText!.trim()}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFFB7B0C6)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _questionController,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(
                    hintText: 'Ask Claude...',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => _sendQuestion(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: state.isLoading ? null : _sendQuestion,
                icon: const Icon(Icons.send),
                tooltip: 'Send question',
              ),
            ],
          ),
        ),
        Expanded(
          child: state.messages.isEmpty
              ? Center(
                  child: Text(
                    'Ask a question about this book.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: state.messages.length,
                  itemBuilder: (context, index) {
                    final msg = state.messages[index];
                    return _MessageBubble(message: msg);
                  },
                ),
        ),
        if (state.isLoading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ClaudeMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withAlpha(40),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Text(message.question),
          ),
          const SizedBox(height: 8),
          MarkdownBody(
            data: message.answer,
            styleSheet: MarkdownStyleSheet(
              p: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
