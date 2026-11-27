import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'player_panel_chrome.dart';

/// 原版「信息显示」面板：七行，每行可选 关 / 左上 / 右上 / 左下 / 右下。
/// 迷你进度条只有 关 / 开。
class InfoPanel extends StatelessWidget {
  const InfoPanel({
    super.key,
    required this.positions,
    required this.onChanged,
    required this.miniProgress,
    required this.onMiniProgress,
  });

  static const rows = [
    ('battery', '电量'),
    ('clock', '当前时间'),
    ('frameRate', '视频帧率'),
    ('resolution', '分辨率'),
    ('progress', '播放进度'),
    ('speed', '网速'),
  ];
  static const spots = [
    ('off', '关'),
    ('topLeft', '左上'),
    ('topRight', '右上'),
    ('bottomLeft', '左下'),
    ('bottomRight', '右下'),
  ];

  final Map<String, String> positions;
  final ValueChanged<Map<String, String>> onChanged;
  final bool miniProgress;
  final ValueChanged<bool> onMiniProgress;

  @override
  Widget build(BuildContext context) => PlayerPanelShell(
    width: 400,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PanelGroupHeader('信息显示'),
        for (final (key, label) in rows)
          _Row(
            label: label,
            value: positions[key] ?? 'off',
            onChanged: (value) => onChanged({...positions, key: value}),
          ),
        _MiniRow(on: miniProgress, onChanged: onMiniProgress),
        const PanelNote(
          '关闭时这一项不占用画面。桌面没有电量/网速读数时显示 --，不编造数据。',
        ),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 3, 10, 3),
    child: Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Colors.white),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 4,
            children: [
              for (final (slug, text) in InfoPanel.spots)
                _Chip(
                  label: text,
                  selected: value == slug,
                  onTap: () => onChanged(slug),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MiniRow extends StatelessWidget {
  const _MiniRow({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 3, 10, 3),
    child: Row(
      children: [
        const SizedBox(
          width: 78,
          child: Text(
            '迷你进度条',
            style: TextStyle(fontSize: 12.5, color: Colors.white),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 4,
            children: [
              _Chip(label: '关', selected: !on, onTap: () => onChanged(false)),
              _Chip(label: '开', selected: on, onTap: () => onChanged(true)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? Colors.white : const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: selected ? Colors.black : LcbColors.textSecondary,
        ),
      ),
    ),
  );
}
