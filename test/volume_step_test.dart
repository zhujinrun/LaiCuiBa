import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/player/volume_step.dart';

void main() {
  test('向下滚是调小，向上滚是调大', () {
    expect(steppedVolume(50, 40), 45);
    expect(steppedVolume(50, -40), 55);
  });

  test('夹在 mpv 的 0-100 里', () {
    // media_kit 的音量就是 0-100；滚过头不能变成负数或 120，
    // 那两头上古版本会直接 assert 掉一个 debug 构建。
    expect(steppedVolume(0, 40), 0);
    expect(steppedVolume(100, -40), 100);
    expect(steppedVolume(2, 40), 0);
    expect(steppedVolume(99, -40), 100);
  });

  test('没有滚动量就不动', () {
    expect(steppedVolume(42, 0), 42);
  });
}
