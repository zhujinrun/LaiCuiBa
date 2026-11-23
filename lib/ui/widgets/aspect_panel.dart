import 'package:flutter/material.dart';

import '../../services/picture.dart';
import 'player_panel_chrome.dart';

/// 播放页底栏「比例」按钮弹出的面板：画面比例六档。
///
/// 原来比例和画面调节挤在一个「画面」面板里，两件事得先找到上面那一半才能改
/// 下面那一半。原版是「比例」「画面」两个按钮，这里照办：比例立刻改 `BoxFit`，
/// 画面调节改的是 mpv 的亮度/对比度那几个属性，本来就不是一类操作。
class AspectPanel extends StatelessWidget {
  const AspectPanel({super.key, required this.mode, required this.onMode});

  final AspectMode mode;
  final ValueChanged<AspectMode> onMode;

  @override
  Widget build(BuildContext context) {
    return PlayerPanelShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelGroupHeader('画面比例'),
          for (final m in AspectMode.values)
            PanelRow(
              label: m.label,
              subtitle: m.description,
              selected: m == mode,
              onTap: () => onMode(m),
            ),
        ],
      ),
    );
  }
}
