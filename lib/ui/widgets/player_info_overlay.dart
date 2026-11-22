import 'package:flutter/material.dart';

import '../../services/player_info.dart';

/// 播放页的「信息显示」常驻浮层：一行小字钉在画面角落，不随操作菜单隐藏。
///
/// 每一项是「分辨率 1920×1080」，拿不到的值（帧率/码率要等流开始解码）显示
/// `--`——原版在 ExoPlayer 下也是这么处理的。纯渲染，数据在调用方已经算好。
class PlayerInfoOverlay extends StatelessWidget {
  const PlayerInfoOverlay({super.key, required this.facts});

  /// 有序的信息项；顺序就是显示顺序。
  final List<PlayerInfoFact> facts;

  @override
  Widget build(BuildContext context) {
    final text = facts.map((f) => '${f.label} ${f.value ?? '--'}').join('  ·  ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Color(0xFFE6E6EA)),
      ),
    );
  }
}

/// 播放页最底下的「迷你进度条」：一根常驻细线，蓝色=已播、浅蓝=已缓冲。
///
/// 原版叫「迷你进度条」：画面最底下一根线，详情页小窗、全屏、系统悬浮小窗
/// 都显示。这里只做全屏这一处；总时长未知时只有缓冲段。
class MiniProgressBar extends StatelessWidget {
  const MiniProgressBar({
    super.key,
    required this.position,
    required this.buffer,
    required this.duration,
    this.color,
  });

  final Duration position;
  final Duration buffer;
  final Duration duration;

  /// 已播段的颜色，默认主题紫（对齐主进度条 activeColor）。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final played = totalMs <= 0
        ? 0.0
        : (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final buffered = totalMs <= 0
        ? 0.0
        : (buffer.inMilliseconds / totalMs).clamp(0.0, 1.0);
    return SizedBox(
      height: 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: buffered,
            child: const ColoredBox(color: Color(0x6658A6FF)),
          ),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: played,
            child: ColoredBox(color: color ?? const Color(0xFF7B68EE)),
          ),
        ],
      ),
    );
  }
}
