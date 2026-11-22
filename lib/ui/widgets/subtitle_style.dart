import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 视频上那行字幕的样式。
///
/// 桌面上 media_kit 没开 libass（`PlayerConfiguration.libass` 默认 false），所以
/// 字幕不是 mpv 画出来的，而是 `Video` 把 `sub-text` 当成一个 Flutter `Text` 画
/// 在画面上——这也是为什么设置页里的字号能立刻生效，不需要重开文件：它改的是
/// 一个 `TextStyle`，不是 mpv 的属性。
///
/// 尺寸档位在 [presets] 里，设置页与测试共用同一张表，界面上的「大」和真机上
/// 的字号不会对不上。
abstract final class LcbSubtitleStyle {
  /// 32 是 media_kit 的默认字号，也是这里「标准」的取值——不改设置时画面跟
  /// 原版一致。
  static const standard = 32;

  static const presets = <int, String>{
    24: '小',
    32: '标准',
    42: '大',
    54: '特大',
  };

  /// 最接近 [size] 的档位名，认不出就退回「标准」。
  static String labelOf(int size) {
    var best = standard;
    for (final s in presets.keys) {
      if ((s - size).abs() < (best - size).abs()) best = s;
    }
    return presets[best] ?? '标准';
  }

  static SubtitleViewConfiguration of(int size) {
    final px = size < 16 ? 16 : (size > 96 ? 96 : size);
    return SubtitleViewConfiguration(
      style: TextStyle(
        height: 1.35,
        fontSize: px.toDouble(),
        letterSpacing: 0,
        wordSpacing: 0,
        color: const Color(0xffffffff),
        fontWeight: FontWeight.w500,
        // 半透明底：白字压在雪景、白墙这类画面上仍然读得出来。
        backgroundColor: const Color(0x99000000),
      ),
      textAlign: TextAlign.center,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
    );
  }
}
