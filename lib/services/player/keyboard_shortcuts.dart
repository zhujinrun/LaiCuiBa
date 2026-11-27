/// 播放页的键盘快捷键映射。
///
/// 原版从 app.so 能确认的只有「老板键」和「摸鱼小窗快捷键」两项可配置全局热键；
/// 上下键音量、左右键 ±10 秒是用户明确要求补上的播放页操作，不是原版对齐项
/// （见 .workbuddy/memory/topics/parity.md）。
///
/// 这里只做「键 → 动作」的纯映射，副作用留在 PlayerPage：这样键位可以在不
/// 启动真实 mpv 的情况下单测，滚轮/按钮/键盘三条路也能共用同一套动作实现。
library;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' show ShortcutActivator, SingleActivator;

enum PlayerShortcut {
  volumeUp,
  volumeDown,
  seekBack,
  seekForward,
  miniWindow,
}

/// 物理按键按位置识别：[LogicalKeyboardKey] 不会被输入法切换成别的字符，
/// 所以中文输入法开着时方向键与 P 依然有效。
PlayerShortcut? playerShortcutFor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.arrowUp) return PlayerShortcut.volumeUp;
  if (key == LogicalKeyboardKey.arrowDown) return PlayerShortcut.volumeDown;
  if (key == LogicalKeyboardKey.arrowLeft) return PlayerShortcut.seekBack;
  if (key == LogicalKeyboardKey.arrowRight) return PlayerShortcut.seekForward;
  if (key == LogicalKeyboardKey.keyP) return PlayerShortcut.miniWindow;
  return null;
}

/// 每个动作对应的 `CallbackShortcuts` 绑定。
///
/// 带修饰键的组合（Ctrl+K 搜索、Ctrl+Alt+H 老板键）不在这里：前者属于 shell，
/// 后者走 shell 自己的应用内热键，避免和播放页的焦点范围混在一起。
Map<ShortcutActivator, PlayerShortcut> get playerShortcutBindings =>
    const {
      SingleActivator(LogicalKeyboardKey.arrowUp): PlayerShortcut.volumeUp,
      SingleActivator(LogicalKeyboardKey.arrowDown): PlayerShortcut.volumeDown,
      SingleActivator(LogicalKeyboardKey.arrowLeft): PlayerShortcut.seekBack,
      SingleActivator(LogicalKeyboardKey.arrowRight): PlayerShortcut.seekForward,
      SingleActivator(LogicalKeyboardKey.keyP): PlayerShortcut.miniWindow,
    };

/// 老板键：Ctrl+Alt+H。
///
/// 当前构建是应用内热键（shell 有焦点时生效），不是原版那种系统全局快捷键；
/// 触发后暂停并最小化，回来时点任务栏图标、手动点播放继续。为什么不注册
/// Win32 全局热键：那要起消息窗口 + 后台 isolate，无法在常驻进程里验证。
bool isBossKey(LogicalKeyboardKey key, {required bool control, required bool alt}) =>
    key == LogicalKeyboardKey.keyH && control && alt;

/// 老板键的完整绑定，供 shell 的 `CallbackShortcuts` 使用。
ShortcutActivator get bossKeyActivator =>
    const SingleActivator(LogicalKeyboardKey.keyH, control: true, alt: true);
