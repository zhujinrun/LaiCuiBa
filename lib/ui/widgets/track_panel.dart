import 'package:flutter/material.dart';

import '../../services/track_choice.dart';
import 'player_panel_chrome.dart';

/// 播放页的「轨道」面板：线路 / 画质 / 声音。
///
/// 字幕已经拆到自己的按钮下，这里只剩换线路和换轨道。底栏也只在**真的有的
/// 切**时才摆这个按钮（多条线路、多条视频轨或多条音轨）；一条流的常见情况
/// 下它根本不出现，底栏就和原版一样是 倍速/字幕/弹幕/比例/画面/信息/选集。
///
/// 三组都只在真的有的选时才出现——一条视频轨的「画质」、只有一个语言音轨的
/// 「声音」都是假选项，摆上去只会让人以为点错了。
class TrackPanel extends StatelessWidget {
  const TrackPanel({
    super.key,
    required this.choices,
    this.lines = const [],
    this.lineIndex = 0,
    this.onLine,
    this.onVideo,
    this.onAudio,
  });

  final TrackChoices choices;

  /// 源给的多条播放线路。只有一条（或没有）时不显示线路组——那时候换线路
  /// 等于重新解析同一个地址，白等一次。
  final List<String> lines;
  final int lineIndex;
  final ValueChanged<int>? onLine;

  final ValueChanged<TrackOption>? onVideo;
  final ValueChanged<TrackOption>? onAudio;

  bool get _hasLines => lines.length > 1 && onLine != null;

  /// 底栏要不要摆这个按钮：有线路可换，或者有多条视频/音轨。
  static bool worthShowing({
    required TrackChoices choices,
    List<String> lines = const [],
    ValueChanged<int>? onLine,
  }) =>
      (lines.length > 1 && onLine != null) ||
      choices.hasVideoChoice ||
      choices.hasAudioChoice;

  @override
  Widget build(BuildContext context) {
    final hasAnything =
        _hasLines || choices.hasVideoChoice || choices.hasAudioChoice;
    if (!hasAnything) {
      return const PlayerPanelShell(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Text(
            '这条流没有可切换的线路或音轨',
            style: TextStyle(fontSize: 12.5, color: Color(0xFFB8B8BE)),
          ),
        ),
      );
    }
    return PlayerPanelShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasLines) ...[
            const PanelGroupHeader('线路'),
            for (var i = 0; i < lines.length; i++)
              PanelRow(
                label: lines[i],
                selected: i == lineIndex,
                onTap: () => onLine!(i),
              ),
          ],
          if (choices.hasVideoChoice) ...[
            const PanelGroupHeader('画质'),
            for (final t in choices.video)
              PanelRow(
                label: t.label,
                detail: t.detail,
                selected: t.id == choices.videoId,
                onTap: () => onVideo?.call(t),
              ),
          ],
          if (choices.hasAudioChoice) ...[
            const PanelGroupHeader('声音'),
            for (final t in choices.audio)
              PanelRow(
                label: t.label,
                detail: t.detail,
                selected: t.id == choices.audioId,
                onTap: () => onAudio?.call(t),
              ),
          ],
        ],
      ),
    );
  }
}
