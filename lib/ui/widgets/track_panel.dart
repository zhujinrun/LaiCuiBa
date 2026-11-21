import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/track_choice.dart';

/// 播放页右下角弹出的轨道面板：线路 / 画质 / 声音 / 字幕。
///
/// 四组都只在**真的有的选**时才出现——一条视频轨的「画质」、只有一个语言音轨的
/// 「声音」都是假选项，摆上去只会让人以为点错了。字幕是例外：只要这条流带字幕，
/// 「关闭」本身就是一个合法的选择。
class TrackPanel extends StatelessWidget {
  const TrackPanel({
    super.key,
    required this.choices,
    this.lines = const [],
    this.lineIndex = 0,
    this.onLine,
    this.onVideo,
    this.onAudio,
    this.onSubtitle,
  });

  final TrackChoices choices;

  /// 源给的多条播放线路。只有一条（或没有）时不显示线路组——那时候换线路
  /// 等于重新解析同一个地址，白等一次。
  final List<String> lines;
  final int lineIndex;
  final ValueChanged<int>? onLine;

  final ValueChanged<TrackOption>? onVideo;
  final ValueChanged<TrackOption>? onAudio;
  final ValueChanged<TrackOption>? onSubtitle;

  bool get _hasLines => lines.length > 1 && onLine != null;

  bool get _hasAnything =>
      _hasLines ||
      choices.hasVideoChoice ||
      choices.hasAudioChoice ||
      choices.hasSubtitleChoice;

  @override
  Widget build(BuildContext context) {
    // 一行 34、一组标题 24。默认能装下 4 组十来条轨；窗口矮的时候跟着收，
    // 剩下的靠滚动，而不是把最后几组切在屏幕外。
    final screen = MediaQuery.maybeOf(context)?.size.height ?? 720;
    final maxHeight = (screen - 220).clamp(180.0, 560.0);
    return Container(
      width: 288,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: const Color(0xF21C1C1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1FFFFFFF)),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: !_hasAnything
          /* 播放器还没报出轨道，或者这条流本来就没什么可切。 */
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Text(
                '这条流没有可切换的轨道',
                style: TextStyle(fontSize: 12.5, color: Color(0xFFB8B8BE)),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_hasLines) ...[
                    const _GroupHeader('线路'),
                    for (var i = 0; i < lines.length; i++)
                      _Row(
                        label: lines[i],
                        selected: i == lineIndex,
                        onTap: () => onLine!(i),
                      ),
                  ],
                  if (choices.hasVideoChoice) ...[
                    const _GroupHeader('画质'),
                    for (final t in choices.video)
                      _Row(
                        label: t.label,
                        detail: t.detail,
                        selected: t.id == choices.videoId,
                        onTap: () => onVideo?.call(t),
                      ),
                  ],
                  if (choices.hasAudioChoice) ...[
                    const _GroupHeader('声音'),
                    for (final t in choices.audio)
                      _Row(
                        label: t.label,
                        detail: t.detail,
                        selected: t.id == choices.audioId,
                        onTap: () => onAudio?.call(t),
                      ),
                  ],
                  if (choices.hasSubtitleChoice) ...[
                    const _GroupHeader('字幕'),
                    _Row(
                      label: '关闭',
                      selected: choices.subtitleOff,
                      onTap: () => onSubtitle?.call(
                        const TrackOption(id: 'no'),
                      ),
                    ),
                    for (final t in choices.subtitle)
                      _Row(
                        label: t.label,
                        detail: t.detail,
                        selected: t.id == choices.subtitleId,
                        onTap: () => onSubtitle?.call(t),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: Color(0xFF8E8E93),
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.selected ? LcbColors.primary : Colors.white;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          color: _hover ? const Color(0x14FFFFFF) : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: color,
                  ),
                ),
              ),
              if (widget.detail != null) ...[
                const SizedBox(width: 10),
                Text(
                  widget.detail!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ],
              if (widget.selected) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check, size: 15, color: LcbColors.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
