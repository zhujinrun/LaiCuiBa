import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'player_panel_chrome.dart';

/// 原版底栏聊天气泡打开的是「弹幕」设置面板，不是一键开关。
/// 这里只摆真能生效的项：显示开关、屏蔽顶部/底部、字号和透明度。
class DanmakuPanel extends StatelessWidget {
  const DanmakuPanel({
    super.key,
    required this.on,
    required this.onToggle,
    required this.blockTop,
    required this.onBlockTop,
    required this.blockBottom,
    required this.onBlockBottom,
    required this.opacity,
    required this.onOpacity,
    required this.fontSize,
    required this.onFontSize,
    required this.hasSource,
  });

  final bool on;
  final VoidCallback onToggle;
  final bool blockTop;
  final ValueChanged<bool> onBlockTop;
  final bool blockBottom;
  final ValueChanged<bool> onBlockBottom;
  final double opacity;
  final ValueChanged<double> onOpacity;
  final double fontSize;
  final ValueChanged<double> onFontSize;
  final bool hasSource;

  @override
  Widget build(BuildContext context) => PlayerPanelShell(
    width: 320,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SwitchRow(label: '显示弹幕', value: on, onChanged: (_) => onToggle()),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
          child: Text(
            hasSource
                ? '弹幕源已配置，打开后自动匹配这一集'
                : '未配置弹幕源，可在 设置 > 弹幕源 中添加',
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF8E8E93),
              height: 1.4,
            ),
          ),
        ),
        const PanelGroupHeader('屏蔽区域'),
        _SwitchRow(
          label: '屏蔽顶部弹幕',
          value: blockTop,
          onChanged: onBlockTop,
        ),
        _SwitchRow(
          label: '屏蔽底部弹幕',
          value: blockBottom,
          onChanged: onBlockBottom,
        ),
        const PanelGroupHeader('样式'),
        _SliderRow(
          label: '不透明度',
          value: opacity,
          min: 0.2,
          max: 1.0,
          onChanged: onOpacity,
          format: (v) => '${(v * 100).round()}%',
        ),
        _SliderRow(
          label: '字号',
          value: fontSize,
          min: 12,
          max: 36,
          onChanged: onFontSize,
          format: (v) => '${v.round()}',
        ),
      ],
    ),
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.white),
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: LcbColors.primary,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.format,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 66,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Colors.white),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: LcbColors.primary,
              inactiveTrackColor: const Color(0x44FFFFFF),
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              trackHeight: 3,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            format(value),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
          ),
        ),
      ],
    ),
  );
}
