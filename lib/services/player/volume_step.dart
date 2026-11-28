/// 音量的一次滚轮 / 方向键步进。
///
/// 底栏原来有一根滑杆，原版的底栏没有它，所以音量改由「鼠标停在画面上滚」
/// 和上下方向键来调。这里保留纯逻辑，是因为它有两个必须成立的性质：夹在
/// 允许的音量区间内，上下方向不能反。
library;

/// 原版音量上限 150%（默认 100%），media_kit/mpv 的音量属性接受 0-150。
const double maxVolume = 150;

/// 默认音量，原版为 100%。
const double defaultVolume = 100;

/// 滚轮一格 5%，方向键一次 10%。
const double wheelVolumeStep = 5;
const double keyVolumeStep = 10;

/// [dy] 是 `PointerScrollEvent.scrollDelta.dy`：向上滚 / 上方向键为负。
/// 滚轮传 [wheelVolumeStep]，方向键传 [keyVolumeStep]，最后一律夹在 0-150。
double steppedVolume(
  double current,
  double dy, {
  double step = wheelVolumeStep,
}) {
  if (dy == 0) return current;
  final next = current + (dy < 0 ? step : -step);
  return next.clamp(0.0, maxVolume);
}
