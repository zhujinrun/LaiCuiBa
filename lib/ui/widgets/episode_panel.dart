import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 播放页右下角的选集面板。
///
/// 底栏原本只有「上一集 / 下一集」两个箭头：看 40 集的剧想跳到第 30 集，只能
/// 点 29 次。原版播放页的底栏里有一个「选集」，这里补上同一件事。
///
/// 面板只负责「显示并回报一个下标」：集名是源给的（可能是「第12集」「12」或者
/// 干脆是文件名的片段），切换由播放页交给上层，和详情页选集的出口一致。
class EpisodePanel extends StatelessWidget {
  const EpisodePanel({
    super.key,
    required this.episodes,
    required this.currentIndex,
    required this.onPick,
    this.title = '选集',
  });

  final List<String> episodes;

  /// 正在播的那一集；-1 表示不知道（比如一个没有集号的作品）。
  final int currentIndex;

  final ValueChanged<int> onPick;

  /// 面板标题，详情页那边叫「选集」，播放页沿用同一个词。
  final String title;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.maybeOf(context)?.size.height ?? 720;
    final maxHeight = (screen - 220).clamp(200.0, 560.0);
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '共 ${episodes.length} 集',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0x8CFFFFFF),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < episodes.length; i++)
                    _EpisodeChip(
                      key: ValueKey('episode-chip-$i'),
                      label: _labelOf(i),
                      current: i == currentIndex,
                      onTap: i == currentIndex ? null : () => onPick(i),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 源给的集名可能只是「12」，也可能是一条完整标题；两种都要能认出来，所以
  /// 只做「太长的截断」，不重排内容。
  String _labelOf(int index) {
    final raw = episodes[index].trim();
    if (raw.isEmpty) return '${index + 1}';
    return raw.length > 12 ? raw.substring(0, 12) : raw;
  }
}

class _EpisodeChip extends StatefulWidget {
  const _EpisodeChip({
    super.key,
    required this.label,
    required this.current,
    this.onTap,
  });

  final String label;
  final bool current;
  final VoidCallback? onTap;

  @override
  State<_EpisodeChip> createState() => _EpisodeChipState();
}

class _EpisodeChipState extends State<_EpisodeChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    final bg = current
        ? LcbColors.primaryDim
        : _hover
        ? const Color(0x2EFFFFFF)
        : const Color(0x14FFFFFF);
    return MouseRegion(
      cursor: current ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 64,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: current ? FontWeight.w600 : FontWeight.w400,
              color: current ? Colors.white : const Color(0xE6FFFFFF),
            ),
          ),
        ),
      ),
    );
  }
}
