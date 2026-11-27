import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'player_panel_chrome.dart';

/// 播放页底栏「倍速」按钮弹出的面板。
///
/// 原版不是档位菜单，而是一根 0.25x–10x 的连续滑块（刻度 0.25/1/2/3/10），
/// 下面写着「播放时长按画面临时用 2x」和设置页的长按倍速入口。
class RatePanel extends StatelessWidget {
  const RatePanel({super.key, required this.rate, required this.onRate});

  final double rate;
  final ValueChanged<double> onRate;

  @override
  Widget build(BuildContext context) {
    final value = rate.clamp(0.25, 10.0);
    return PlayerPanelShell(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Text(
              value == value.roundToDouble()
                  ? '${value.toInt()}x'
                  : '${value.toStringAsFixed(2)}x',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: LcbColors.primary,
              inactiveTrackColor: const Color(0x44FFFFFF),
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              trackHeight: 3,
            ),
            child: Slider(value: value, min: 0.25, max: 10, onChanged: onRate),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0.25x', style: _tick),
                Text('1x', style: _tick),
                Text('2x', style: _tick),
                Text('3x', style: _tick),
                Text('10x', style: _tick),
              ],
            ),
          ),
          const PanelNote(
            '拖动滑块调倍速。播放时长按画面临时用 2x，可在 设置 > 播放 > 长按倍速 里改。',
          ),
        ],
      ),
    );
  }
}

const TextStyle _tick = TextStyle(fontSize: 10.5, color: Color(0xFF8E8E93));
