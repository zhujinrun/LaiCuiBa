import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/picture.dart';
import 'player_panel_chrome.dart';

/// 播放页底栏「画面」按钮弹出的面板：亮度 / 对比度 / 饱和度 / 色相 / 伽马。
///
/// 比例已经拆到「比例」按钮下，这里只剩调节——五个量都是 mpv 属性，滑一下
/// 改一下，窗口关掉也不会自己回去（值跟着设置存）。
class PicturePanel extends StatelessWidget {
  const PicturePanel({
    super.key,
    required this.adjust,
    required this.onAdjust,
    this.onFullScreen,
    this.onMiniWindow,
    this.onScreenshot,
    this.fullScreen = false,
    this.miniWindow = false,
    this.casting = false,
    this.onCast,
    this.onStopCast,
  });

  final PictureAdjust adjust;
  final ValueChanged<PictureAdjust> onAdjust;
  final VoidCallback? onFullScreen;
  final VoidCallback? onMiniWindow;
  final VoidCallback? onScreenshot;
  final bool fullScreen;
  final bool miniWindow;

  /// 投屏状态与入口（原版底栏那一排里有「投屏」）。
  final bool casting;
  final VoidCallback? onCast;
  final VoidCallback? onStopCast;

  @override
  Widget build(BuildContext context) {
    return PlayerPanelShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelGroupHeader('画面调节'),
          _Slider(
            label: '亮度',
            value: adjust.brightness,
            onChanged: (v) => onAdjust(adjust.copyWith(brightness: v)),
          ),
          _Slider(
            label: '对比度',
            value: adjust.contrast,
            onChanged: (v) => onAdjust(adjust.copyWith(contrast: v)),
          ),
          _Slider(
            label: '饱和度',
            value: adjust.saturation,
            onChanged: (v) => onAdjust(adjust.copyWith(saturation: v)),
          ),
          _Slider(
            label: '色相',
            value: adjust.hue,
            onChanged: (v) => onAdjust(adjust.copyWith(hue: v)),
          ),
          _Slider(
            label: '伽马',
            value: adjust.gamma,
            onChanged: (v) => onAdjust(adjust.copyWith(gamma: v)),
          ),
          if (!adjust.isNeutral)
            _ResetRow(onTap: () => onAdjust(PictureAdjust.none)),
          const PanelGroupHeader('窗口'),
          PanelRow(
            label: '全屏（F）',
            selected: fullScreen,
            detail: fullScreen ? '退出全屏' : null,
            onTap: onFullScreen ?? () {},
          ),
          PanelRow(
            label: '小窗播放',
            selected: miniWindow,
            detail: miniWindow ? '还原窗口' : null,
            onTap: onMiniWindow ?? () {},
          ),
          PanelRow(
            label: '截图',
            selected: false,
            onTap: onScreenshot ?? () {},
          ),
          if (casting)
            PanelRow(
              label: '退出投屏',
              selected: false,
              onTap: onStopCast ?? () {},
            )
          else
            PanelRow(
              label: '投屏',
              selected: false,
              onTap: onCast ?? () {},
            ),
          const PanelNote('0% 是原始画面；这里的亮度和屏幕亮度分开'),
        ],
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: Colors.white),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.toDouble().clamp(-100.0, 100.0),
              min: -100,
              max: 100,
              activeColor: LcbColors.primary,
              inactiveColor: const Color(0x33FFFFFF),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, color: Color(0xFFB8B8BE)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResetRow extends StatelessWidget {
  const _ResetRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        child: const Text(
          '恢复原始画面',
          style: TextStyle(fontSize: 13, color: LcbColors.primary),
        ),
      ),
    );
  }
}
