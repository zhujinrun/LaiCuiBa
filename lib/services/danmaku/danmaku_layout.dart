import 'danmaku_api.dart';

/// 弹幕画在哪一区。
enum DanmakuZone {
  /// 从右往左滚。
  scroll,

  /// 钉在画面上方。
  top,

  /// 钉在画面下方（控制条之上）。
  bottom,
}

/// 一条被排上位置的弹幕。
///
/// 位置在这里就算好（第几条轨道、从哪毫秒开始、占多宽多久），绘制时只按当前
/// 播放进度算 x/y，不再做碰撞判断——否则每帧都要重排一遍，弹幕一多就掉帧。
class DanmakuPlacement {
  const DanmakuPlacement({
    required this.comment,
    required this.zone,
    required this.lane,
    required this.startMs,
    required this.durationMs,
    required this.width,
  });

  final DanmakuComment comment;
  final DanmakuZone zone;
  final int lane;
  final int startMs;
  final int durationMs;
  final double width;

  int get endMs => startMs + durationMs;

  bool visibleAt(int positionMs) =>
      positionMs >= startMs && positionMs < endMs;
}

/// 一屏弹幕的排版结果。
///
/// 纯逻辑、不碰 Widget：给定画布尺寸、字号测量函数和原始弹幕表，算出每条弹幕
/// 在哪条轨道、什么时候出现、横向怎么走。单元测试直接传入假的测量函数就能断言
/// 轨道不重叠。
class DanmakuLayout {
  const DanmakuLayout({
    required this.width,
    required this.height,
    required this.laneHeight,
    required this.topInset,
    required this.bottomInset,
    required this.placements,
  });

  /// 排版。
  ///
  /// - [measure] 返回这条弹幕渲染后的像素宽度。绘制层用 `TextPainter` 量，
  ///   测试里给个固定值即可——排版与绘制必须用同一个宽度，否则轨道会算错。
  /// - [speedPxPerMs] 是滚动速度（像素/毫秒），默认 0.15 即 150 px/s，
  ///   1920 宽的画面上一条弹幕走完全程约 9 秒，与原版观感一致。
  /// - [blockTop] / [blockBottom] 直接丢掉对应区的弹幕，而不是画了再裁掉。
  factory DanmakuLayout.assign(
    List<DanmakuComment> comments, {
    required double width,
    required double height,
    required double Function(DanmakuComment) measure,
    double laneHeight = 32,
    double speedPxPerMs = 0.15,
    int fixedMs = 4000,
    double topInset = 12,
    double bottomInset = 96,
    bool blockTop = false,
    bool blockBottom = false,
  }) {
    if (width <= 0 || height <= 0 || laneHeight <= 0) {
      return DanmakuLayout(
        width: width,
        height: height,
        laneHeight: laneHeight,
        topInset: topInset,
        bottomInset: bottomInset,
        placements: const [],
      );
    }
    final usable = (height - topInset - bottomInset).clamp(laneHeight, height);
    final scrollLanes = (usable * 0.62 / laneHeight).floor().clamp(1, 40);
    final fixedRows = (usable * 0.18 / laneHeight).floor().clamp(1, 8);

    // 轨道空闲时刻：滚动轨记「尾巴整条进画」的时间，固定轨记「这一条消失」的时间。
    final scrollFree = List<int>.filled(scrollLanes, 0);
    final topBusy = List<int>.filled(fixedRows, 0);
    final bottomBusy = List<int>.filled(fixedRows, 0);

    final out = <DanmakuPlacement>[];
    for (final c in comments) {
      if (c.text.trim().isEmpty) continue;
      final w = measure(c);
      if (w <= 0) continue;
      final zone = c.mode == DanmakuComment.top
          ? DanmakuZone.top
          : c.mode == DanmakuComment.bottom
              ? DanmakuZone.bottom
              : DanmakuZone.scroll;
      if (zone == DanmakuZone.top && blockTop) continue;
      if (zone == DanmakuZone.bottom && blockBottom) continue;

      if (zone == DanmakuZone.scroll) {
        final duration = ((width + w) / speedPxPerMs).round();
        final lane = _freeLane(scrollFree, c.timeMs);
        if (lane == null) continue; // 满屏了，宁可丢一条也不叠着画
        // 尾巴完全进画之后这条轨道才能再来一条：按几何比例算，不用经验常数。
        final enterMs =
            c.timeMs + (duration * w / (width + w)).round();
        if (enterMs < c.timeMs) continue;
        scrollFree[lane] = enterMs;
        out.add(DanmakuPlacement(
          comment: c,
          zone: zone,
          lane: lane,
          startMs: c.timeMs,
          durationMs: duration,
          width: w,
        ));
      } else {
        final busy = zone == DanmakuZone.top ? topBusy : bottomBusy;
        final lane = _freeLane(busy, c.timeMs);
        if (lane == null) continue;
        busy[lane] = c.timeMs + fixedMs;
        out.add(DanmakuPlacement(
          comment: c,
          zone: zone,
          lane: lane,
          startMs: c.timeMs,
          durationMs: fixedMs,
          width: w,
        ));
      }
    }
    out.sort((a, b) => a.startMs.compareTo(b.startMs));
    return DanmakuLayout(
      width: width,
      height: height,
      laneHeight: laneHeight,
      topInset: topInset,
      bottomInset: bottomInset,
      placements: out,
    );
  }

  final double width;
  final double height;
  final double laneHeight;
  final double topInset;
  final double bottomInset;
  final List<DanmakuPlacement> placements;

  bool get isEmpty => placements.isEmpty;

  /// 当前时刻应该画出来的弹幕。
  List<DanmakuPlacement> activeAt(int positionMs) {
    if (placements.isEmpty) return const [];
    final out = <DanmakuPlacement>[];
    for (final p in placements) {
      if (p.startMs > positionMs) break; // 已按开始时间排序
      if (positionMs < p.endMs) out.add(p);
    }
    return out;
  }

  double xOf(DanmakuPlacement p, int positionMs) {
    if (p.zone != DanmakuZone.scroll) return (width - p.width) / 2;
    final progress = (positionMs - p.startMs) / p.durationMs;
    // 起点在右边缘外，终点在左边缘外：进出画都不留半个字。
    return width - (width + p.width) * progress;
  }

  double yOf(DanmakuPlacement p) {
    if (p.zone == DanmakuZone.bottom) {
      return height - bottomInset - (p.lane + 1) * laneHeight;
    }
    return topInset + p.lane * laneHeight;
  }
}

/// 找一条在 [timeMs] 已经空出来的轨道；全满则返回 null（这一条丢掉）。
///
/// 按序号从小到大挑，也就是"从上往下填"：弹幕会贴着画面上沿排，读者的眼睛不用
/// 在屏幕上找下一条出现在哪。轨道全满时宁可丢这一条——叠着画会让两行字糊成一片。
int? _freeLane(List<int> freeAt, int timeMs) {
  for (var i = 0; i < freeAt.length; i++) {
    if (freeAt[i] <= timeMs) return i;
  }
  return null;
}
