import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme.dart';
import '../../models/models.dart';

/// 播放页 — 全屏视频播放。
///
/// Renders the video through media_kit's libmpv backend and paints a minimal
/// control bar on top: play/pause, a draggable seek bar with the position and
/// duration, a rate picker and a volume slider. The controls fade away while
/// playing and reappear on hover or click.
///
/// The URL is resolved *before* this page opens (see [PlayerPage.open]): the
/// caller hands in a concrete [url] from the detail's [MediaItem.playLines] or
/// from the source's `play` action, so this page stays a pure renderer with no
/// knowledge of the spider.
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.title,
    required this.url,
    this.subtitle,
    this.headers = const {},
    this.episodes = const [],
    this.episodeIndex,
    this.startAt,
    this.onEpisode,
    this.onClose,
    this.onProgress,
  });

  /// Title shown in the top bar.
  final String title;

  /// The playable URL (m3u8 / mp4 / …) handed to the player.
  final String url;

  /// Secondary line under the title, e.g. the site or line name.
  final String? subtitle;

  /// Headers the request needs. A WebDAV share has no token in its URL, so the
  /// Basic credential has to ride along here; every other source passes none.
  final Map<String, String> headers;

  /// Episode labels for the next/prev controls and the title suffix. Empty for
  /// films.
  final List<String> episodes;

  /// Index of the episode currently playing, when [episodes] is non-empty.
  final int? episodeIndex;

  /// Where to seek on open, for 续播.
  final Duration? startAt;

  /// Invoked with the next episode index when the user steps; null hides the
  /// step controls (films).
  final ValueChanged<int>? onEpisode;

  final VoidCallback? onClose;

  /// Reports the final playback position and total duration when the player is
  /// torn down, so the shell can persist it for 续播.
  final void Function(Duration position, Duration duration)? onProgress;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<double>? _rateSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = true;
  bool _buffering = false;
  double _volume = 100;
  double _rate = 1.0;
  bool _seeking = false;
  double _seekValue = 0;

  bool _controlsVisible = true;
  Timer? _hideTimer;

  bool get _hasNext => widget.episodes.isNotEmpty && widget.episodeIndex != null;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.stream.position.listen((d) {
      if (!_seeking) _position = d;
      if (mounted) setState(() {});
    });
    _durationSub = _player.stream.duration.listen((d) {
      if (d > Duration.zero) _duration = d;
      if (mounted) setState(() {});
    });
    _playingSub = _player.stream.playing.listen((p) {
      _playing = p;
      if (mounted) setState(() {});
    });
    _player.stream.buffering.listen((b) {
      _buffering = b;
      if (mounted) setState(() {});
    });
    _volumeSub = _player.stream.volume.listen((v) {
      _volume = v;
      if (mounted) setState(() {});
    });
    _rateSub = _player.stream.rate.listen((r) {
      _rate = r;
      if (mounted) setState(() {});
    });

    _open();
  }

  Future<void> _open() async {
    try {
      await _player.open(
        Media(
          widget.url,
          start: widget.startAt,
          httpHeaders: {'User-Agent': _ua, ...widget.headers},
        ),
        play: true,
      );
    } catch (e) {
      debugPrint('LcbPlayer: open failed: $e');
    }
    _scheduleHide();
  }

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_playing) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing && !_seeking) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _togglePlay() {
    if (_playing) {
      _player.pause();
    } else {
      _player.play();
    }
    _scheduleHide();
  }

  String get _currentLabel {
    final i = widget.episodeIndex;
    if (i != null && i < widget.episodes.length) return widget.episodes[i];
    return '';
  }

  String get _titleLine {
    final label = _currentLabel;
    if (label.isEmpty) return widget.title;
    return '${widget.title} · $label';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _volumeSub?.cancel();
    _rateSub?.cancel();
    // Report the final position before tearing the player down; this is the
    // single reliable moment to capture where the user left off.
    widget.onProgress?.call(_position, _duration);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Video(
              controller: _controller,
              controls: NoVideoControls,
              fit: BoxFit.contain,
            ),
          ),
          if (_buffering)
            const Center(
              child: CircularProgressIndicator(color: LcbColors.primary),
            ),
          // A single full-surface tap layer toggles the controls; it sits under
          // the bars so the bars' own buttons still win the hit test.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
            ),
          ),
          _TopBar(
            title: _titleLine,
            subtitle: widget.subtitle,
            onClose: widget.onClose,
            visible: _controlsVisible,
          ),
          _BottomBar(
            playing: _playing,
            buffering: _buffering,
            position: _position,
            duration: _duration,
            volume: _volume,
            rate: _rate,
            visible: _controlsVisible,
            hasNext: _hasNext,
            hasPrev:
                widget.episodeIndex != null && widget.episodeIndex! > 0,
            onTogglePlay: _togglePlay,
            onSeek: (d) => _player.seek(d),
            onSeekStart: () => setState(() => _seeking = true),
            onSeekEnd: () {
              _seeking = false;
              final target = Duration(
                milliseconds:
                    (_seekValue * _duration.inMilliseconds).round(),
              );
              _player.seek(target);
              _scheduleHide();
            },
            onSeekChanged: (v) => _seekValue = v,
            onVolume: (v) => _player.setVolume(v),
            onRate: (r) => _player.setRate(r),
            onNext: _hasNext
                ? () => widget.onEpisode!(widget.episodeIndex! + 1)
                : null,
            onPrev: (widget.episodeIndex != null && widget.episodeIndex! > 0)
                ? () => widget.onEpisode!(widget.episodeIndex! - 1)
                : null,
          ),
        ],
      ),
    );
  }
}

/// The dark top strip: close button, title, subtitle.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onClose,
    required this.visible,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !visible,
        child: Container(
          height: 64,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xB3000000), Color(0x00000000)],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _RoundButton(
                icon: Icons.arrow_back,
                onTap: onClose ?? () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB8B8BE),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dark bottom strip: seek bar, play/pause, time, step controls, rate and
/// volume.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.playing,
    required this.buffering,
    required this.position,
    required this.duration,
    required this.volume,
    required this.rate,
    required this.visible,
    required this.hasNext,
    required this.hasPrev,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onSeekStart,
    required this.onSeekEnd,
    required this.onSeekChanged,
    required this.onVolume,
    required this.onRate,
    this.onNext,
    this.onPrev,
  });

  final bool playing;
  final bool buffering;
  final Duration position;
  final Duration duration;
  final double volume;
  final double rate;
  final bool visible;
  final bool hasNext;
  final bool hasPrev;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onVolume;
  final ValueChanged<double> onRate;
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xB3000000), Color(0x00000000)],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Seek bar row.
                Row(
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
                        onChangeStart: (_) => onSeekStart(),
                        onChanged: (v) {
                          onSeekChanged(v);
                          // Live-preview the scrub position in the label.
                        },
                        onChangeEnd: (v) => onSeekEnd(),
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
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (onPrev != null) ...[
                      _RoundButton(
                        icon: Icons.skip_previous,
                        onTap: onPrev,
                      ),
                      const SizedBox(width: 8),
                    ],
                    _RoundButton(
                      icon: playing
                          ? Icons.pause
                          : Icons.play_arrow,
                      onTap: onTogglePlay,
                    ),
                    if (onNext != null) ...[
                      const SizedBox(width: 8),
                      _RoundButton(
                        icon: Icons.skip_next,
                        onTap: onNext,
                      ),
                    ],
                    const SizedBox(width: 16),
                    if (buffering)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      ),
                    const Spacer(),
                    _RateButton(rate: rate, onRate: onRate),
                    const SizedBox(width: 16),
                    VolumeControl(volume: volume, onVolume: onVolume),
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
  const _RoundButton({required this.icon, this.onTap});

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

class _RateButton extends StatefulWidget {
  const _RateButton({required this.rate, required this.onRate});

  final double rate;
  final ValueChanged<double> onRate;

  @override
  State<_RateButton> createState() => _RateButtonState();
}

class _RateButtonState extends State<_RateButton> {
  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      initialValue: widget.rate,
      onSelected: widget.onRate,
      color: const Color(0xFF2A2A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      itemBuilder: (_) => [
        for (final r in _rates)
          PopupMenuItem(
            value: r,
            child: Text(
              r == 1.0 ? '${r.toStringAsFixed(1)} 倍速' : '$r 倍速',
              style: TextStyle(
                fontSize: 13,
                color: r == widget.rate ? LcbColors.primary : Colors.white,
              ),
            ),
          ),
      ],
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          '${widget.rate} 倍速',
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
      ),
    );
  }
}

@visibleForTesting
class VolumeControl extends StatelessWidget {
  const VolumeControl({super.key, required this.volume, required this.onVolume});

  final double volume;
  final ValueChanged<double> onVolume;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          volume <= 0 ? Icons.volume_off : Icons.volume_up,
          size: 20,
          color: Colors.white,
        ),
        SizedBox(
          width: 90,
          child: Slider(
            // media_kit carries volume as 0-100; Slider wants 0-1. Mapping here
            // keeps the raw value in one place so a 100 never lands on a 0-1
            // slider (which asserts and, in a debug build, kills the app).
            value: volume / 100,
            activeColor: LcbColors.primary,
            inactiveColor: const Color(0x66FFFFFF),
            onChanged: (v) => onVolume(v * 100),
          ),
        ),
      ],
    );
  }
}
