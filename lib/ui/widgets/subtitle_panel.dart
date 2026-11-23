import 'package:flutter/material.dart';

import '../../services/track_choice.dart';
import 'player_panel_chrome.dart';

/// 播放页底栏「字幕」按钮弹出的面板：这一集能挂的字幕，加上本地文件。
///
/// 字幕原来和线路/画质/声音挤在同一个「轨道」面板里，可它其实是四种轨道里
/// 唯一每天都要动的一种。原版把它单独做成一个按钮，这里照办。
///
/// 即使这条流一条字幕轨都没有，面板也不是空的：自己挑一个本地文件，正是被
/// 内嵌字幕坑过的人最想找的出路。
class SubtitlePanel extends StatelessWidget {
  const SubtitlePanel({
    super.key,
    required this.choices,
    this.onSubtitle,
    this.externalSubtitleLabel,
    this.onPickSubtitleFile,
    this.onClearSubtitleFile,
  });

  final TrackChoices choices;
  final ValueChanged<TrackOption>? onSubtitle;

  /// 这一集挂着的外挂字幕文件名；null 表示没挂。
  final String? externalSubtitleLabel;

  /// 打开本地字幕文件选择器。桌面才有，手机上这里是 null。
  final VoidCallback? onPickSubtitleFile;

  /// 取消外挂字幕；没挂时是 null。
  final VoidCallback? onClearSubtitleFile;

  @override
  Widget build(BuildContext context) {
    final tracks = choices.subtitle;
    final hasFiles = onPickSubtitleFile != null;
    return PlayerPanelShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Text(
                '这一集没有内嵌字幕',
                style: TextStyle(fontSize: 12.5, color: Color(0xFFB8B8BE)),
              ),
            )
          else ...[
            const PanelGroupHeader('字幕'),
            PanelRow(
              label: '关闭',
              selected: choices.subtitleOff && externalSubtitleLabel == null,
              onTap: () => onSubtitle?.call(const TrackOption(id: 'no')),
            ),
            for (final t in tracks)
              PanelRow(
                label: t.label,
                detail: t.detail,
                selected: t.id == choices.subtitleId,
                onTap: () => onSubtitle?.call(t),
              ),
          ],
          if (hasFiles) ...[
            const PanelGroupHeader('本地文件'),
            PanelRow(
              label: externalSubtitleLabel == null
                  ? '选择本地字幕文件…'
                  : '外挂：$externalSubtitleLabel',
              selected: externalSubtitleLabel != null,
              onTap: onPickSubtitleFile!,
            ),
            if (externalSubtitleLabel != null && onClearSubtitleFile != null)
              PanelRow(
                label: '不再使用外挂字幕',
                selected: false,
                onTap: onClearSubtitleFile!,
              ),
            const PanelNote('支持 srt / ass / vtt；挂上之后这一集会被记住。'),
          ],
        ],
      ),
    );
  }
}
