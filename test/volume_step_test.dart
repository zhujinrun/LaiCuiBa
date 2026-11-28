import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/player/volume_step.dart';

void main() {
  test('向下滚是调小，向上滚是调大', () {
    expect(steppedVolume(50, 40), 45);
    expect(steppedVolume(50, -40), 55);
  });

  test('夹在原版的 0-150 里（默认 100，可继续加到 150）', () {
    // 原版音量上限 150%、默认 100%；滚过头不能变负数或超过 150，
    // mpv 的 volume 属性接受这个区间，两头上古版本会 assert 掉 debug 构建。
    expect(steppedVolume(0, 40), 0);
    expect(steppedVolume(150, -40), 150);
    expect(steppedVolume(2, 40), 0);
    expect(steppedVolume(149, -40), 150);
    // 从默认 100 往上能加到 150，不会卡在 100。
    expect(steppedVolume(100, -40), 105);
    expect(steppedVolume(148, -40), 150);
  });

  test('方向键一步 10%，滚轮一格 5%', () {
    expect(steppedVolume(100, -1, step: keyVolumeStep), 110);
    expect(steppedVolume(100, 1, step: keyVolumeStep), 90);
    // 方向键到顶也夹在 150，不会变成 160。
    expect(steppedVolume(145, -1, step: keyVolumeStep), 150);
    // 滚轮仍是 5%。
    expect(steppedVolume(100, -40), 105);
  });

  test('没有滚动量就不动', () {
    expect(steppedVolume(42, 0), 42);
    expect(steppedVolume(42, 0, step: keyVolumeStep), 42);
  });
}
