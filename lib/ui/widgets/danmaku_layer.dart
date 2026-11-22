import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/danmaku/danmaku_api.dart';
import '../../services/danmaku/danmaku_layout.dart';

/// 叠在视频上的弹幕层。
///
/// 播放页只把「当前进度」和「在不在播」丢进来，层内部用 [Ticker] 把两次进度
/// 事件之间的时间补齐——否则弹幕会随着进度流（约每 200ms 一次）一卡一卡地跳。
///
/// 排版（哪条在哪条轨道）只在「画布尺寸变了 / 弹幕表变了」时算一次，每帧只做
/// 一次 `activeAt` 过滤 + 画字；`IgnorePointer` 保证点击仍然落到播放页的手势层。
class DanmakuLayer extends StatefulWidget {
  const DanmakuLayer({
    super.key,
    required this.comments,
    required this.position,
    this.playing = true,
    this.blockTop = false,
    this.blockBottom = false,
    this.fontSize = 22,
    this.opacity = 0.92,
  });

  final List<DanmakuComment> comments;

  /// 播放器最近一次报上来的位置。层内部从这里开始插值。
  final Duration position;
  final bool playing;
  final bool blockTop;
  final bool blockBottom;
  final double fontSize;
  final double opacity;

  @override
  State<DanmakuLayer> createState() => _DanmakuLayerState();
}

class _DanmakuLayerState extends State<DanmakuLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// 从 [_baseMs] 起走过的真实时间。用 Stopwatch 而不是 Ticker 的 elapsed，
  /// 是因为 Ticker 每次 `start()` 都会把 elapsed 归零，频繁重启会抖。
  final Stopwatch _since = Stopwatch();

  /// 当前该画到哪一毫秒。画布只监听这个值，播放页的重建不会带着整页重绘。
  final ValueNotifier<int> _now = ValueNotifier<int>(0);

  int _baseMs = 0;

  @override
  void initState() {
    super.initState();
    _baseMs = widget.position.inMilliseconds;
    _ticker = createTicker(_onTick);
    _syncPlayback();
  }

  @override
  void didUpdateWidget(covariant DanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      // 每次拿到真实进度就以它为准：慢了就追上，拖进度条就直接跳过去。
      _baseMs = widget.position.inMilliseconds;
      _since
        ..reset()
        ..start();
      _now.value = _baseMs;
    }
    if (oldWidget.playing != widget.playing ||
        oldWidget.comments.length != widget.comments.length) {
      _syncPlayback();
    }
  }

  void _syncPlayback() {
    final shouldRun = widget.playing && widget.comments.isNotEmpty;
    if (shouldRun && !_ticker.isTicking) {
      _since
        ..reset()
        ..start();
      _ticker.start();
    } else if (!shouldRun && _ticker.isTicking) {
      _ticker.stop();
      _since.stop();
    }
    if (!shouldRun) _now.value = _baseMs;
  }

  void _onTick(Duration _) {
    _now.value = _baseMs + _since.elapsedMilliseconds;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.comments.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _now,
        builder: (context, _) => CustomPaint(
          painter: _DanmakuPainter(
            comments: widget.comments,
            positionMs: _now.value,
            blockTop: widget.blockTop,
            blockBottom: widget.blockBottom,
            fontSize: widget.fontSize,
            opacity: widget.opacity,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter({
    required this.comments,
    required this.positionMs,
    required this.blockTop,
    required this.blockBottom,
    required this.fontSize,
    required this.opacity,
  });

  final List<DanmakuComment> comments;
  final int positionMs;
  final bool blockTop;
  final bool blockBottom;
  final double fontSize;
  final double opacity;

  /// 排版结果按「尺寸 + 弹幕表 + 屏蔽开关」缓存。每帧重排上千条会掉帧，而这三样
  /// 在一次播放里基本不变。
  DanmakuLayout? _layout;
  Size _layoutSize = Size.zero;
  int _layoutCount = -1;
  bool _layoutTop = false;
  bool _layoutBottom = false;

  DanmakuLayout _ensureLayout(Size size) {
    final cached = _layout;
    if (cached != null &&
        _layoutSize == size &&
        _layoutCount == comments.length &&
        _layoutTop == blockTop &&
        _layoutBottom == blockBottom) {
      return cached;
    }
    final layout = DanmakuLayout.assign(
      comments,
      width: size.width,
      height: size.height,
      laneHeight: fontSize + 10,
      measure: _measure,
      blockTop: blockTop,
      blockBottom: blockBottom,
    );
    _layout = layout;
    _layoutSize = size;
    _layoutCount = comments.length;
    _layoutTop = blockTop;
    _layoutBottom = blockBottom;
    return layout;
  }

  /// 用真实排版宽度，而不是「字数 × 字号」估——中英混排时估算能差 40%。
  double _measure(DanmakuComment c) {
    final painter = TextPainter(
      text: TextSpan(
        text: c.text,
        style: TextStyle(fontSize: fontSize, height: 1.1),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final layout = _ensureLayout(size);
    if (layout.isEmpty) return;
    final active = layout.activeAt(positionMs);
    if (active.isEmpty) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    for (final p in active) {
      final x = layout.xOf(p, positionMs);
      final y = layout.yOf(p);
      final style = TextStyle(
        fontSize: fontSize,
        height: 1.1,
        fontWeight: FontWeight.w500,
      );
      final painter = TextPainter(
        text: TextSpan(
          text: p.comment.text,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4
              ..color = const Color(0xCC000000),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      painter.paint(canvas, Offset(x, y - painter.height / 2 + layout.laneHeight / 2));

      final color = Color(0xFF000000 | p.comment.color)
          .withValues(alpha: opacity.clamp(0.0, 1.0));
      final body = TextPainter(
        text: TextSpan(text: p.comment.text, style: style.copyWith(color: color)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      body.paint(canvas, Offset(x, y - body.height / 2 + layout.laneHeight / 2));
      body.dispose();
      painter.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter old) =>
      old.positionMs != positionMs ||
      old.comments.length != comments.length ||
      old.blockTop != blockTop ||
      old.blockBottom != blockBottom ||
      old.fontSize != fontSize;
}
