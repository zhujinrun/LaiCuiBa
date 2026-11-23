/// 音量的一次滚轮步进。
///
/// 底栏原来有一根 0-100 的滑杆，原版的底栏没有它，所以音量改由「鼠标停在画面
/// 上滚」来调。这里保留纯逻辑，是因为它有两个必须成立的性质：夹在 mpv 的
/// 0-100 之内，上下滚方向不能反。
library;

/// 滚轮一格 = 5%。[dy] 是 `PointerScrollEvent.scrollDelta.dy`：向下滚为正。
double steppedVolume(double current, double dy) {
  if (dy == 0) return current;
  final next = current + (dy < 0 ? 5 : -5);
  return next.clamp(0.0, 100.0);
}
