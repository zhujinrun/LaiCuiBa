import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/track_choice.dart';
import 'player_panel_chrome.dart';

/// 播放页底栏 CC 按钮弹出的「字幕」抽屉。原版顶部有四个页签：
/// 字幕 / 次字幕 / AI 翻译 / 样式；第一个页签里是关闭字幕、搜索在线字幕、
/// 选择本地字幕文件。没有内嵌字幕时照原版明说，不摆假轨道。
class SubtitlePanel extends StatefulWidget {
  const SubtitlePanel({
    super.key,
    required this.choices,
    this.onSubtitle,
    this.externalSubtitleLabel,
    this.onPickSubtitleFile,
    this.onClearSubtitleFile,
    this.onSearchSubtitles,
    this.aiOn = false,
    this.onToggleAi,
  });

  final TrackChoices choices;
  final ValueChanged<TrackOption>? onSubtitle;
  final String? externalSubtitleLabel;
  final VoidCallback? onPickSubtitleFile;
  final VoidCallback? onClearSubtitleFile;
  final VoidCallback? onSearchSubtitles;
  final bool aiOn;
  final VoidCallback? onToggleAi;

  @override
  State<SubtitlePanel> createState() => _SubtitlePanelState();
}

class _SubtitlePanelState extends State<SubtitlePanel> {
  int _tab = 0;
  static const _tabs = ['字幕', '次字幕', 'AI 翻译', '样式'];

  @override
  Widget build(BuildContext context) {
    return PlayerPanelShell(
      width: 330,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  _TabChip(
                    label: _tabs[i],
                    selected: _tab == i,
                    onTap: () => setState(() => _tab = i),
                  ),
                ],
              ],
            ),
          ),
          if (_tab == 0) _mainTab(),
          if (_tab == 1)
            const PanelNote('这一集没有独立次字幕。需要双语对照时可用 AI 翻译页签。'),
          if (_tab == 2) ...[
            PanelRow(
              label: widget.aiOn ? 'AI 翻译已开' : 'AI 翻译本集字幕',
              selected: widget.aiOn,
              detail: widget.aiOn ? '关闭' : null,
              onTap: widget.onToggleAi ?? () {},
            ),
            const PanelNote(
              '接口和 Key 在 设置 > 播放 > 字幕 > AI 翻译；Key 只保存在本机。',
            ),
          ],
          if (_tab == 3)
            const PanelNote('字幕字号与颜色在 设置 > 播放 > 字幕 > 样式 里调整。'),
        ],
      ),
    );
  }

  Widget _mainTab() {
    final tracks = widget.choices.subtitle;
    final hasFiles = widget.onPickSubtitleFile != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tracks.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text(
              '这个视频没有内嵌字幕。可以选一个本地字幕文件。',
              style: TextStyle(fontSize: 12.5, color: Color(0xFFB8B8BE)),
            ),
          )
        else ...[
          const PanelGroupHeader('字幕'),
          PanelRow(
            label: '关闭字幕',
            selected:
                widget.choices.subtitleOff &&
                widget.externalSubtitleLabel == null,
            onTap: () => widget.onSubtitle?.call(const TrackOption(id: 'no')),
          ),
          for (final t in tracks)
            PanelRow(
              label: t.label,
              detail: t.detail,
              selected: t.id == widget.choices.subtitleId,
              onTap: () => widget.onSubtitle?.call(t),
            ),
        ],
        const PanelGroupHeader('在线字幕'),
        PanelRow(
          label: '搜索在线字幕…',
          selected: false,
          onTap: widget.onSearchSubtitles ?? () {},
        ),
        if (hasFiles) ...[
          const PanelGroupHeader('本地文件'),
          PanelRow(
            label: widget.externalSubtitleLabel == null
                ? '选择本地字幕文件…'
                : '外挂：${widget.externalSubtitleLabel}',
            selected: widget.externalSubtitleLabel != null,
            onTap: widget.onPickSubtitleFile!,
          ),
          if (widget.externalSubtitleLabel != null &&
              widget.onClearSubtitleFile != null)
            PanelRow(
              label: '不再使用外挂字幕',
              selected: false,
              onTap: widget.onClearSubtitleFile!,
            ),
          const PanelNote('支持 srt / ass / vtt；挂上之后这一集会被记住。'),
        ],
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? LcbColors.primary : const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          color: selected ? Colors.black : LcbColors.textSecondary,
        ),
      ),
    ),
  );
}
