import 'package:flutter/material.dart';

import 'emoji_data.dart';
import 'emoji_font.dart';
import 'emoji_search.dart';

/// Full categorized emoji picker (grid + category tabs + keyword search).
class EmojiPicker extends StatefulWidget {
  /// Called when an emoji is selected.
  final ValueChanged<String> onSelected;

  /// Highlight quick reactions strip at the top (for message reactions).
  final bool showQuickReactions;

  /// Optional height for embedded use (null = expand).
  final double? height;

  const EmojiPicker({
    super.key,
    required this.onSelected,
    this.showQuickReactions = false,
    this.height,
  });

  /// Show as a modal bottom sheet; returns the chosen emoji or null.
  static Future<String?> show(
    BuildContext context, {
    bool showQuickReactions = false,
    String title = 'Emoji',
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final h = MediaQuery.sizeOf(context).height * 0.55;
        return SafeArea(
          child: SizedBox(
            height: h,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: EmojiPicker(
                    showQuickReactions: showQuickReactions,
                    onSelected: (e) => Navigator.pop(context, e),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'emoji_search');
  String _query = '';
  bool _fontsReady = EmojiGlyphs.ready;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: EmojiCatalog.categories.length,
      vsync: this,
    );
    if (!_fontsReady) {
      EmojiGlyphs.ensureReady().then((_) {
        if (mounted) setState(() => _fontsReady = true);
      });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    setState(() => _query = v);
    // Keep caret in the search field after structural sibling updates.
    if (!_searchFocus.hasFocus) {
      _searchFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_fontsReady) {
      final loading = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(height: 12),
            Text('Loading emoji…'),
          ],
        ),
      );
      if (widget.height != null) {
        return SizedBox(height: widget.height, child: loading);
      }
      return loading;
    }

    final searching = _query.trim().isNotEmpty;
    final results = searching ? EmojiSearch.search(_query) : const <String>[];

    // Keep a stable Column child order so the TextField is never reparented
    // (reparenting on first keystroke was stealing focus).
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showQuickReactions)
          AnimatedSize(
            duration: const Duration(milliseconds: 120),
            alignment: Alignment.topCenter,
            child: searching
                ? const SizedBox(width: double.infinity)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: SizedBox(
                          height: 44,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final e in EmojiCatalog.quickReactions)
                                _EmojiCell(
                                  emoji: e,
                                  size: 40,
                                  onTap: () => widget.onSelected(e),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            // Stable identity across rebuilds.
            key: const ValueKey('emoji_search_field'),
            controller: _search,
            focusNode: _searchFocus,
            decoration: InputDecoration(
              hintText: 'Search emoji…',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                        _searchFocus.requestFocus();
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              filled: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: _onQueryChanged,
          ),
        ),
        // Content area: always a single Expanded with IndexedStack so tabs
        // stay mounted and the search field never shifts index mid-tree.
        Expanded(
          child: IndexedStack(
            index: searching ? 1 : 0,
            sizing: StackFit.expand,
            children: [
              // 0 — browse by category
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      for (final c in EmojiCatalog.categories)
                        Tab(
                          child: Text(
                            c.icon,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        for (final c in EmojiCatalog.categories)
                          _EmojiGrid(
                            emojis: c.emojis,
                            onSelected: widget.onSelected,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              // 1 — search results
              results.isEmpty && searching
                  ? Center(
                      child: Text(
                        'No matches for “${_query.trim()}”',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: Text(
                            searching
                                ? '${results.length} result${results.length == 1 ? '' : 's'}'
                                : '',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        Expanded(
                          child: _EmojiGrid(
                            emojis: results,
                            onSelected: widget.onSelected,
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ],
    );

    if (widget.height != null) {
      return SizedBox(height: widget.height, child: body);
    }
    return body;
  }
}

class _EmojiGrid extends StatelessWidget {
  final List<String> emojis;
  final ValueChanged<String> onSelected;

  const _EmojiGrid({required this.emojis, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: emojis.length,
      itemBuilder: (context, i) {
        final e = emojis[i];
        return _EmojiCell(
          emoji: e,
          onTap: () => onSelected(e),
        );
      },
    );
  }
}

class _EmojiCell extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;
  final double size;

  const _EmojiCell({
    required this.emoji,
    required this.onTap,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Center(
        child: Text(
          emoji,
          style: EmojiGlyphs.style(fontSize: size * 0.62),
        ),
      ),
    );
  }
}
