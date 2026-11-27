/// 老板键的信号总线。
///
/// shell 收到 Ctrl+Alt+H 后发一次信号，播放器监听并暂停；shell 同时最小化
/// 窗口。当前构建是应用内热键，窗口藏起来后收不到第二次按键，所以恢复靠用户
/// 点任务栏图标回到应用，再手动点播放——这里不替用户擅自续播。
library;

import 'package:flutter/foundation.dart';

class BossKeyNotifier extends ValueNotifier<int> {
  BossKeyNotifier() : super(0);

  /// 每次按下都递增，播放器靠值变化触发，而不必关心按下次数。
  void fire() => value++;
}
