import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/player/volume_step.dart' show maxVolume;

/// 播放页底部那条悬浮控制条，完全照用户给的原版全屏截图排：
///
/// * 一根细进度条在上，紫色已播 + 白色滑块；
/// * 下一行左边是 `01:41 / 48:25` 加 上一集 / 快退10 / 播放暂停 / 快进10 / 下一集；
/// * 右边是一排**图标**：倍速 / 字幕 / 弹幕 / 比例 / 画面 / 信息 / 投屏 / 选集 /
///   画中画 / 音量 / 全屏。
///
/// 原版没有「轨道」按钮，也没有片头胶囊；这两件事分别放在画面面板和右键进度条里。
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
    this.onCast,
    this.casting = false,
    this.onMiniWindow,
    this.onFullScreen,
    this.miniWindow = false,
    this.fullScreen = false,
    this.volume = 100,
    this.onVolumeChanged,
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

  /// 倍速：原版是右上角那一排里的小图标，点开给几档。
  final VoidCallback onRatePanel;
  final bool rateOpen;
  final VoidCallback onSubtitle;
  final bool subtitleOpen;
  final VoidCallback onDanmaku;
  final bool danmakuOn;
  final bool danmakuAsking;

  /// 轨道（线路/画质/声音）保留参数兼容旧调用，但按钮已经移进画面面板。
  final VoidCallback? onTracks;
  final bool tracksOpen;

  final VoidCallback onAspect;
  final bool aspectOpen;
  final VoidCallback onPicture;
  final bool pictureOpen;
  final VoidCallback onInfo;
  final bool infoOpen;
  final VoidCallback onEpisodes;
  final bool episodesOpen;
  final int episodeCount;

  /// 右键（或长按）进度条打开本剧片头片尾；原版底栏没有这个按钮。
  final VoidCallback onSkipPanel;

  final VoidCallback? onNext;
  final VoidCallback? onPrev;
  final VoidCallback? onBack10;
  final VoidCallback? onForward10;
  final VoidCallback? onCast;
  final bool casting;
  final VoidCallback? onMiniWindow;
  final VoidCallback? onFullScreen;
  final bool miniWindow;
  final bool fullScreen;

  /// 音量滑杆：原版底栏确实有，滚轮调音量的做法只是我们早先的误判。
  final double volume;
  final ValueChanged<double>? onVolumeChanged;

  /// player_buttons 设置：原版截图是图标，所以默认应走图标；文字只是可选项。
  final bool iconMode;

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
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
            // 原版在 1360 的窗口里这条是 1088 宽（80%）；1920 时约 1536。
            constraints: BoxConstraints(
              minWidth: 480,
              maxWidth: math.min(MediaQuery.sizeOf(context).width * 0.8, 1600),
            ),
            decoration: BoxDecoration(
              color: const Color(0xCC1A1A20),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 22,
                  child: Tooltip(
                    message: '右键设置本剧片头片尾',
                    waitDuration: const Duration(milliseconds: 800),
                    child: GestureDetector(
                      onSecondaryTap: onSkipPanel,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5,
                          ),
                          overlayShape: SliderComponentShape.noOverlay,
                          activeTrackColor: LcbColors.primary,
                          inactiveTrackColor: const Color(0x66FFFFFF),
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: value,
                          onChangeStart: totalMs <= 0
                              ? null
                              : (_) => onSeekStart(),
                          onChanged: totalMs <= 0 ? null : onSeekChanged,
                          onChangeEnd: totalMs <= 0 ? null : (_) => onSeekEnd(),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_fmt(position)} / ${_fmt(duration)}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFFDDDDDD),
                          ),
                        ),
                        const SizedBox(width: 14),
                        if (onPrev != null) ...[
                          _RoundButton(
                            key: const ValueKey('player-prev'),
                            icon: Icons.skip_previous,
                            onTap: onPrev,
                          ),
                          const SizedBox(width: 2),
                        ],
                        _RoundButton(
                          key: const ValueKey('player-back-10'),
                          icon: Icons.replay_10,
                          onTap: onBack10,
                        ),
                        const SizedBox(width: 2),
                        _RoundButton(
                          key: const ValueKey('player-play-pause'),
                          icon: playing ? Icons.pause : Icons.play_arrow,
                          onTap: onTogglePlay,
                        ),
                        const SizedBox(width: 2),
                        _RoundButton(
                          key: const ValueKey('player-forward-10'),
                          icon: Icons.forward_10,
                          onTap: onForward10,
                        ),
                        if (onNext != null) ...[
                          const SizedBox(width: 2),
                          _RoundButton(
                            key: const ValueKey('player-next'),
                            icon: Icons.skip_next,
                            onTap: onNext,
                          ),
                        ],
                        if (buffering) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ],
                    ),
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
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _BarButton(
                                key: const ValueKey('player-rate'),
                                label: '倍速',
                                icon: Icons.speed,
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
                              const SizedBox(width: 4),
                              _BarButton(
                                key: const ValueKey('player-cast'),
                                label: '投屏',
                                icon: Icons.cast,
                                active: casting,
                                onTap: onCast ?? () {},
                                iconMode: iconMode,
                              ),
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
                              const SizedBox(width: 4),
                              _BarButton(
                                key: const ValueKey('player-mini-window'),
                                label: '画中画',
                                icon: Icons.picture_in_picture_alt,
                                active: miniWindow,
                                onTap: onMiniWindow ?? () {},
                                iconMode: true,
                              ),
                              const SizedBox(width: 6),
                              _volumeControl(context),
                              const SizedBox(width: 6),
                              _BarButton(
                                key: const ValueKey('player-fullscreen'),
                                label: '全屏',
                                icon: fullScreen
                                    ? Icons.fullscreen_exit
                                    : Icons.fullscreen,
                                active: false,
                                onTap: onFullScreen ?? () {},
                                iconMode: true,
                              ),
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

  Widget _volumeControl(BuildContext context) {
    final icon = volume <= 0 ? Icons.volume_off : Icons.volume_up;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.white),
        const SizedBox(width: 6),
        SizedBox(
          width: 64,
          height: 22,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: Colors.white,
              inactiveTrackColor: const Color(0x55FFFFFF),
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: volume.clamp(0, maxVolume).toDouble(),
              min: 0,
              max: maxVolume,
              onChanged: onVolumeChanged ?? (_) {},
            ),
          ),
        ),
      ],
    );
  }
}

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:$mm:$ss';
  return '$mm:$ss';
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
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _hover ? const Color(0x33FFFFFF) : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(widget.icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

class _BarButton extends StatefulWidget {
  const _BarButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    required this.icon,
    this.iconMode = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData icon;
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
          constraints: const BoxConstraints(minWidth: 28),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? const Color(0x1AFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: widget.iconMode
              ? Icon(widget.icon, size: 18, color: color)
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
