import 'package:flutter/material.dart';

class SearchResult {
  final String cfi;
  final String href;
  final String context;
  final String query;

  const SearchResult({
    required this.cfi,
    this.href = '',
    required this.context,
    required this.query,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
    cfi: json['cfi'] as String? ?? '',
    href: json['href'] as String? ?? '',
    context: json['context'] as String? ?? '',
    query: json['query'] as String? ?? '',
  );
}

class SearchPanel extends StatefulWidget {
  final String initialQuery;
  final FocusNode focusNode;
  final ValueChanged<String> onSearch;
  final ValueChanged<SearchResult> onResultTap;
  final VoidCallback onClose;

  const SearchPanel({
    super.key,
    required this.initialQuery,
    required this.focusNode,
    required this.onSearch,
    required this.onResultTap,
    required this.onClose,
  });

  @override
  State<SearchPanel> createState() => SearchPanelState();
}

class SearchPanelState extends State<SearchPanel> {
  final _controller = TextEditingController();
  List<SearchResult> _results = [];

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;
    _controller.selection = TextSelection.collapsed(
      offset: widget.initialQuery.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void updateResults(List<SearchResult> results) {
    setState(() => _results = results);
  }

  void clear() {
    _controller.clear();
    setState(() => _results = []);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, isMobile ? 16 : 28, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) {
                    setState(() {});
                    widget.onSearch(value);
                  },
                  decoration: InputDecoration(
                    hintText: 'Search in book...',
                    hintStyle: const TextStyle(
                      color: Color(0xFF7c748e),
                      fontSize: 16,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 22,
                      color: Color(0xFF7c748e),
                    ),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _controller.clear();
                              widget.onSearch('');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF252336),
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFFe8e4f0),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 20,
                  color: Color(0xFF7c748e),
                ),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF252336), height: 1),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Text(
                    _controller.text.isEmpty
                        ? 'Type to search in this book'
                        : 'No results found',
                    style: const TextStyle(
                      color: Color(0xFF7c748e),
                      fontSize: 16,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: Color(0xFF252336), height: 1),
                  itemBuilder: (context, index) {
                    final result = _results[index];
                    return _SearchResultTile(
                      result: result,
                      onTap: () => widget.onResultTap(result),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;

  const _SearchResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final q = result.query.toLowerCase();
    final text = result.context;
    final lower = text.toLowerCase();

    final spans = <TextSpan>[];
    var start = 0;
    var idx = lower.indexOf(q);
    while (idx != -1) {
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + q.length),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFFf2a65a),
            backgroundColor: Color(0x30f2a65a),
          ),
        ),
      );
      start = idx + q.length;
      idx = lower.indexOf(q, start);
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: RichText(
          text: TextSpan(
            style: TextStyle(
              color: const Color(0xFFe8e4f0).withAlpha(210),
              fontSize: 15,
              height: 1.5,
            ),
            children: spans,
          ),
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
