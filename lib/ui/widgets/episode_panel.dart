import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 播放页右下角的选集抽屉。原版是逐行列表，顶栏带排序与搜索；
/// 这里保留同样的出口，集名仍是源给的原样（只截断过长文本）。
class EpisodePanel extends StatefulWidget {
  const EpisodePanel({
    super.key,
    required this.episodes,
    required this.currentIndex,
    required this.onPick,
    this.title = '选集',
  });

  final List<String> episodes;
  final int currentIndex;
  final ValueChanged<int> onPick;
  final String title;

  @override
  State<EpisodePanel> createState() => _EpisodePanelState();
}

class _EpisodePanelState extends State<EpisodePanel> {
  String _query = '';
  bool _descending = false;
  bool _searching = false;

  String _labelOf(int index) {
    final raw = widget.episodes[index].trim();
    if (raw.isEmpty) return '${index + 1}';
    return raw.length > 12 ? raw.substring(0, 12) : raw;
  }

  List<int> _visible() {
    final indices = [
      for (var i = 0; i < widget.episodes.length; i++) i,
    ];
    if (_descending) indices.sort((a, b) => b.compareTo(a));
    if (_query.isEmpty) return indices;
    return indices
        .where((i) => _labelOf(i).contains(_query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.maybeOf(context)?.size.height ?? 720;
    final maxHeight = (screen - 220).clamp(200.0, 560.0);
    final visible = _visible();
    return Container(
      width: 372,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: const Color(0xF21C1C1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1FFFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '共 ${widget.episodes.length} 集',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0x8CFFFFFF),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      setState(() => _descending = !_descending),
                  child: Text(_descending ? '倒序' : '正序'),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _query = '';
                  }),
                  icon: Icon(
                    _searching ? Icons.search_off : Icons.search,
                    size: 16,
                  ),
                  color: LcbColors.textSecondary,
                  splashRadius: 18,
                  tooltip: '搜索剧集',
                ),
              ],
            ),
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                autofocus: true,
                onChanged: (value) =>
                    setState(() => _query = value.trim()),
                decoration: const InputDecoration(
                  hintText: '搜索剧集',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          Flexible(
            child: visible.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        '没有匹配的剧集',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: LcbColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: visible.length,
                    itemBuilder: (_, position) {
                      final index = visible[position];
                      return _EpisodeRow(
                        key: ValueKey('episode-chip-$index'),
                        label: _labelOf(index),
                        current: index == widget.currentIndex,
                        onTap: index == widget.currentIndex
                            ? null
                            : () => widget.onPick(index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeRow extends StatefulWidget {
  const _EpisodeRow({
    super.key,
    required this.label,
    required this.current,
    this.onTap,
  });

  final String label;
  final bool current;
  final VoidCallback? onTap;

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.current
        ? const Color(0x33C8B6FF)
        : _hover
        ? const Color(0x2EFFFFFF)
        : const Color(0x14FFFFFF);
    return MouseRegion(
      cursor: widget.current ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 38,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: widget.current
                ? Border.all(color: const Color(0xFFC8B6FF))
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: widget.current ? FontWeight.w600 : FontWeight.w400,
                    color: Colors.white,
                  ),
                ),
              ),
              if (widget.current)
                const Icon(Icons.check, size: 15, color: Color(0xFFC8B6FF)),
            ],
          ),
        ),
      ),
    );
  }
}
