import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 播放页底部那条悬浮控制条。
///
/// 内容照原版：上面一行是时间 + 进度，下面一行左边是快退 / 播放暂停 / 快进 /
/// 上一集 / 下一集，右边是一排**文字**按钮 倍速 / 字幕 / 弹幕 / (轨道) / 比例 /
/// 画面 / 信息 / 选集。
///
/// 两处与原版对齐时删掉的自家东西：
/// * 音量滑杆（原版没有）。音量改成在画面上滚动滚轮调，见播放页的 `_nudgeVolume`。
/// * 「片头 90s」胶囊（原版没有）。本剧片头片尾改成右键进度条打开——它只能边看
///   边设，而进度条就是「当前位置」本身。
///
/// 「轨道」是唯一一个原版没有的按钮，而且只在真的有多条线路/画质/音轨可换时
/// 才出现（[TrackPanel.worthShowing]）；一条流的常见情况下它不出现。

class PlayerBar extends StatelessWidget {
  const PlayerBar({
    super.key,
    required this.playing,
    required this.buffering,
    required this.position,
    required this.duration,
    required this.rate,
    required this.visible,
    required this.onTogglePlay,
    required this.onSeekStart,
    required this.onSeekEnd,
    required this.onSeekChanged,
    required this.onRatePanel,
    required this.rateOpen,
    required this.onSubtitle,
    required this.subtitleOpen,
    required this.onDanmaku,
    required this.danmakuOn,
    required this.danmakuAsking,
    required this.onAspect,
    required this.aspectOpen,
    required this.onPicture,
    required this.pictureOpen,
    required this.onInfo,
    required this.infoOpen,
    required this.onEpisodes,
    required this.episodesOpen,
    required this.episodeCount,
    required this.onSkipPanel,
    this.onTracks,
    this.tracksOpen = false,
    this.onNext,
    this.onPrev,
    this.onBack10,
    this.onForward10,
    this.iconMode = false,
  });

  final bool playing;
  final bool buffering;
  final Duration position;
  final Duration duration;
  final double rate;
  final bool visible;
  final VoidCallback onTogglePlay;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;
  final ValueChanged<double> onSeekChanged;

  /// 倍速：原版是一个「倍速」文字按钮，点开给几档。这里同样是面板。
  final VoidCallback onRatePanel;
  final bool rateOpen;

  /// 底栏右侧那一排**文字**按钮，顺序照原版：
  /// 倍速 / 字幕 / 弹幕 / (轨道) / 比例 / 画面 / 信息 / 选集。
  ///
  /// 原版是纯文字，没有图标也没有胶囊底；我们原来是「图标 + 文字 + 胶囊」，
  /// 条上挤了六个胶囊，看起来比原版重一截。
  final VoidCallback onSubtitle;
  final bool subtitleOpen;
  final VoidCallback onDanmaku;
  final bool danmakuOn;
  final bool danmakuAsking;

  /// 轨道（线路/画质/声音）。null 表示这一条流没什么可换的，按钮不出现。
  final VoidCallback? onTracks;
  final bool tracksOpen;

  final VoidCallback onAspect;
  final bool aspectOpen;

  /// 画面调节（亮度那一组）。比例已经拆到 [onAspect] 下。
  final VoidCallback onPicture;
  final bool pictureOpen;

  final VoidCallback onInfo;
  final bool infoOpen;

  final VoidCallback onEpisodes;
  final bool episodesOpen;
  final int episodeCount;

  /// 本剧片头片尾：右键（或长按）进度条打开。原版底栏没有这个按钮，但它
  /// 只能边看边设，所以挂在「时间轴」这件事本身上。
  final VoidCallback onSkipPanel;

  final VoidCallback? onBack10;
  final VoidCallback? onForward10;

  /// 原版 player_buttons：操作按钮显示成图标而不是文字。
  final bool iconMode;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final value = totalMs <= 0
        ? 0.0
        : (position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !visible,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            // 宽度照原版量出来的比例：1360 的窗口里那条悬浮条是 1088 宽
            // （80%），而不是一个固定值。
            constraints: BoxConstraints(
              minWidth: 480,
              maxWidth: math.min(MediaQuery.sizeOf(context).width * 0.8, 1180),
            ),
            decoration: BoxDecoration(
              color: const Color(0xCC1A1A20),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Seek bar row. 右键它能设本剧片头片尾——原版把这件事放在
                // 「当前位置」上，而进度条就是位置本身。
                Tooltip(
                  // 原版没有「片头」按钮，这件事就藏进了右键里。没有这句
                  // 提示，右键进度条基本等于不存在。
                  message: '右键设置本剧片头片尾',
                  waitDuration: const Duration(milliseconds: 800),
                  child: GestureDetector(
                    onSecondaryTap: onSkipPanel,
                    child: Row(
                      children: [
                        Text(
                          _fmt(position),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFDDDDDD),
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: value,
                            activeColor: LcbColors.primary,
                            inactiveColor: const Color(0x66FFFFFF),
                            // Dragging a bar whose scale is unknown can only
                            // land on zero, so it stays inert until the
                            // duration is in.
                            onChangeStart: totalMs <= 0
                                ? null
                                : (_) => onSeekStart(),
                            onChanged: totalMs <= 0
                                ? null
                                : (v) => onSeekChanged(v),
                            onChangeEnd: totalMs <= 0
                                ? null
                                : (v) => onSeekEnd(),
                          ),
                        ),
                        Text(
                          _fmt(duration),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFDDDDDD),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 左侧这一组的顺序照原版：快退 / 播放暂停 / 快进 /
                        // 上一集 / 下一集。
                        _RoundButton(
                          key: const ValueKey('player-back-10'),
                          icon: Icons.replay_10,
                          onTap: onBack10,
                        ),
                        const SizedBox(width: 4),
                        _RoundButton(
                          key: const ValueKey('player-play-pause'),
                          icon: playing ? Icons.pause : Icons.play_arrow,
                          onTap: onTogglePlay,
                        ),
                        const SizedBox(width: 4),
                        _RoundButton(
                          key: const ValueKey('player-forward-10'),
                          icon: Icons.forward_10,
                          onTap: onForward10,
                        ),
                        const SizedBox(width: 12),
                        if (onPrev != null) ...[
                          _RoundButton(
                            key: const ValueKey('player-prev'),
                            icon: Icons.skip_previous,
                            onTap: onPrev,
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (onNext != null)
                          _RoundButton(
                            key: const ValueKey('player-next'),
                            icon: Icons.skip_next,
                            onTap: onNext,
                          ),
                        if (buffering) ...[
                          const SizedBox(width: 12),
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // 右半边贴右对齐，并且能横向滚：窗口最窄（1040）时这一
                    // 排按钮确实差几十像素，宁可让它滚，也不能把「选集」挤到
                    // 悬浮条外面去。`reverse` 让内容从右边开始排。
                    Expanded(
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _BarButton(
                                key: const ValueKey('player-rate'),
                                label: '倍速',
                                icon: Icons.speed,
                                // 不是 1.0x 的时候亮着，不用点开就知道看过
                                // 之后为什么「感觉快了一点」。
                                active: rateOpen || rate != 1.0,
                                onTap: onRatePanel,
                                iconMode: iconMode,
                              ),
                              const SizedBox(width: 4),
                              _BarButton(
                                key: const ValueKey('player-subtitle'),
                                label: '字幕',
                                icon: Icons.closed_caption,
                                active: subtitleOpen,
                                onTap: onSubtitle,
                                iconMode: iconMode,
                              ),
                              const SizedBox(width: 4),
                              _BarButton(
                                key: const ValueKey('player-danmaku'),
                                label: danmakuAsking ? '弹幕…' : '弹幕',
                                icon: Icons.chat_bubble_outline,
                                active: danmakuOn,
                                onTap: onDanmaku,
                                iconMode: iconMode,
                              ),
                              if (onTracks != null) ...[
                                const SizedBox(width: 4),
                                _BarButton(
                                  key: const ValueKey('player-tracks'),
                                  label: '轨道',
                                  icon: Icons.swap_horiz,
                                  active: tracksOpen,
                                  onTap: onTracks!,
                                iconMode: iconMode,
                                ),
                              ],
                              const SizedBox(width: 4),
                              _BarButton(
                                key: const ValueKey('player-aspect'),
                                label: '比例',
                                icon: Icons.aspect_ratio,
                                active: aspectOpen,
                                onTap: onAspect,
                                iconMode: iconMode,
                              ),
                              const SizedBox(width: 4),
                              _BarButton(
                                key: const ValueKey('player-picture'),
                                label: '画面',
                                icon: Icons.tune,
                                active: pictureOpen,
                                onTap: onPicture,
                                iconMode: iconMode,
                              ),
                              const SizedBox(width: 4),
                              _BarButton(
                                key: const ValueKey('player-info'),
                                label: '信息',
                                icon: Icons.info_outline,
                                active: infoOpen,
                                onTap: onInfo,
                                iconMode: iconMode,
                              ),
                              // 选集：40 集的剧靠两个箭头点过去不现实。
                              if (episodeCount > 1) ...[
                                const SizedBox(width: 4),
                                _BarButton(
                                  key: const ValueKey('player-episodes'),
                                  label: '选集',
                                  icon: Icons.list,
                                  active: episodesOpen,
                                  onTap: onEpisodes,
                                iconMode: iconMode,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

class _RoundButton extends StatefulWidget {
  const _RoundButton({super.key, required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hover ? const Color(0x33FFFFFF) : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(widget.icon, size: 24, color: Colors.white),
        ),
      ),
    );
  }
}

/// A pill in the bottom bar that opens a pop-up panel: an icon plus a short
/// label, filled purple while its panel is open. Used for 片头 and 轨道.
/// 底栏右侧那颗文字按钮。
///
/// 原版这一排是纯文字：没有图标，也没有胶囊底，靠字重和颜色表示「正在开着」。
/// 我们原来每个都是「图标 + 文字 + 胶囊」，六个胶囊在深色条上比原版重一截，
/// 而且图标各自表意（剪刀 = 片头、tune = 轨道）比字更难认。
class _BarButton extends StatefulWidget {
  const _BarButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
    this.iconMode = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final bool iconMode;

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? LcbColors.primary : Colors.white;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 30,
          constraints: const BoxConstraints(minWidth: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // 只在鼠标停上来时给一点点底色：静止时和原版一样是纯文字。
            color: _hover ? const Color(0x1AFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: widget.iconMode && widget.icon != null
              ? Icon(widget.icon, size: 17, color: color)
              : Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                  ),
                ),
        ),
      ),
    );
  }
}
