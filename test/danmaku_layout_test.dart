import 'package:flutter_test/flutter_test.dart';
import 'package:lai_cui_ba/services/danmaku/danmaku_api.dart';
import 'package:lai_cui_ba/services/danmaku/danmaku_layout.dart';

/// Fixed-width measuring keeps the assertions about lanes readable: every
/// comment is 100 px wide, so the arithmetic is easy to check by hand.
double _w(DanmakuComment _) => 100;

DanmakuComment _c(int second, String text, {int mode = 1}) => DanmakuComment(
      timeMs: second * 1000,
      text: text,
      mode: mode,
    );

void main() {
  group('lane assignment', () {
    test('two comments at the same instant get different lanes', () {
      final layout = DanmakuLayout.assign(
        [_c(1, 'a'), _c(1, 'b')],
        width: 1000,
        height: 600,
        measure: _w,
      );
      expect(layout.placements, hasLength(2));
      expect(layout.placements[0].lane, isNot(layout.placements[1].lane));
      expect(layout.placements[0].startMs, 1000);
    });

    test('a lane is reused only once the previous tail has entered', () {
      // width 1000 + text 100 at 0.15 px/ms → 7333 ms on screen, tail enters
      // after 7333 * 100/1100 ≈ 667 ms.
      final layout = DanmakuLayout.assign(
        [_c(1, 'a'), _c(1, 'b'), _c(1, 'c')],
        width: 1000,
        height: 600,
        measure: _w,
      );
      expect(layout.placements, hasLength(3));
      final lanes = layout.placements.map((p) => p.lane).toList();
      expect(lanes.toSet(), hasLength(3), reason: '同一瞬间三条应该分三条轨');

      // 700ms 后第一条的尾巴已经进画，轨道可以再用；但密度没超过轨道数时
      // 排版会挑"最早空出来"的那条，所以这里只断言不叠车道。
      final later = DanmakuLayout.assign(
        [_c(1, 'a'), _c(2, 'b')],
        width: 1000,
        height: 600,
        measure: _w,
      );
      expect(later.placements[1].lane, 0, reason: '轨道 0 先空出来就该先重用');
    });

    test('when every lane is busy the extra comment is dropped, not stacked',
        () {
      // 高度只够一条滚动轨：第二条同时刻的弹幕只能丢掉。
      final layout = DanmakuLayout.assign(
        [_c(1, 'a'), _c(1, 'b')],
        width: 1000,
        height: 90,
        measure: _w,
        topInset: 0,
        bottomInset: 0,
        laneHeight: 32,
      );
      expect(layout.placements, hasLength(1));
    });

    test('top and bottom comments use their own rows', () {
      final layout = DanmakuLayout.assign(
        [
          _c(1, '顶', mode: DanmakuComment.top),
          _c(1, '底', mode: DanmakuComment.bottom),
          _c(1, '滚'),
        ],
        width: 1000,
        height: 600,
        measure: _w,
      );
      final byText = {for (final p in layout.placements) p.comment.text: p};
      expect(byText['顶']!.zone, DanmakuZone.top);
      expect(byText['底']!.zone, DanmakuZone.bottom);
      expect(byText['滚']!.zone, DanmakuZone.scroll);
      // 顶部从画面上沿往下数，底部从下沿往上数。
      expect(layout.yOf(byText['顶']!), lessThan(layout.height / 2));
      expect(layout.yOf(byText['底']!), greaterThan(layout.height / 2));
    });

    test('blockTop / blockBottom drop their zone entirely', () {
      final comments = [
        _c(1, '顶', mode: DanmakuComment.top),
        _c(1, '底', mode: DanmakuComment.bottom),
        _c(1, '滚'),
      ];
      final top = DanmakuLayout.assign(
        comments,
        width: 1000,
        height: 600,
        measure: _w,
        blockTop: true,
      );
      expect(top.placements.map((p) => p.comment.text), isNot(contains('顶')));

      final bottom = DanmakuLayout.assign(
        comments,
        width: 1000,
        height: 600,
        measure: _w,
        blockBottom: true,
      );
      expect(
        bottom.placements.map((p) => p.comment.text),
        isNot(contains('底')),
      );
    });

    test('empty text and zero width are skipped', () {
      final layout = DanmakuLayout.assign(
        [_c(1, '   '), _c(1, 'x')],
        width: 1000,
        height: 600,
        measure: (c) => c.text.trim().isEmpty ? 100 : 0,
      );
      expect(layout.placements, isEmpty);
    });

    test('a zero-sized canvas yields nothing instead of dividing by zero', () {
      final layout = DanmakuLayout.assign(
        [_c(1, 'a')],
        width: 0,
        height: 0,
        measure: _w,
      );
      expect(layout.placements, isEmpty);
    });
  });

  group('timeline', () {
    late DanmakuLayout layout;

    setUp(() {
      layout = DanmakuLayout.assign(
        [_c(1, 'a'), _c(5, 'b')],
        width: 1000,
        height: 600,
        measure: _w,
      );
    });

    test('activeAt only returns what is on screen at that instant', () {
      expect(layout.activeAt(0), isEmpty);
      expect(layout.activeAt(1000).map((p) => p.comment.text), ['a']);
      expect(layout.activeAt(3000).map((p) => p.comment.text), ['a']);
      expect(layout.activeAt(6000).map((p) => p.comment.text), ['a', 'b']);
    });

    test('a scroll starts outside the right edge and ends outside the left',
        () {
      final p = layout.placements.first;
      expect(layout.xOf(p, p.startMs), closeTo(1000, 0.001));
      expect(layout.xOf(p, p.endMs), closeTo(-100, 0.001));
      final mid = layout.xOf(p, p.startMs + p.durationMs ~/ 2);
      expect(mid, inExclusiveRange(-100, 1000));
    });

    test('a fixed comment is centred and stays put', () {
      final fixed = DanmakuLayout.assign(
        [_c(1, '顶', mode: DanmakuComment.top)],
        width: 1000,
        height: 600,
        measure: _w,
      ).placements.single;
      final layout2 = DanmakuLayout.assign(
        [_c(1, '顶', mode: DanmakuComment.top)],
        width: 1000,
        height: 600,
        measure: _w,
      );
      expect(layout2.xOf(fixed, 1000), 450);
      expect(layout2.xOf(fixed, 3000), 450);
    });
  });
}
