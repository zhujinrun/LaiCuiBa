import 'package:flutter/material.dart';

import 'player_panel_chrome.dart';

/// 播放页底栏「倍速」按钮弹出的面板。
///
/// 原来是一个 Material 弹出菜单，深色条上冒出一块系统样式的白/灰框，跟旁边
/// 那几个浮层明显不是一套东西；档位也和设置页对不上。现在和别的面板同一个
/// 外壳，档位与设置页的「默认倍速」共用一张表。
class RatePanel extends StatelessWidget {
  const RatePanel({super.key, required this.rate, required this.onRate});

  final double rate;
  final ValueChanged<double> onRate;

  /// 与设置页「默认倍速」同一组值，两边都改才叫真对齐。
  static const rates = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) {
    return PlayerPanelShell(
      width: 200,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelGroupHeader('播放速度'),
          for (final r in rates)
            PanelRow(
              label: r == 1.0 ? '1.0x（正常）' : '${r}x',
              selected: r == rate,
              onTap: () => onRate(r),
            ),
        ],
      ),
    );
  }
}
