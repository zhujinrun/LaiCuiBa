import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/player/keyboard_shortcuts.dart';

void main() {
  test('方向键与 P 各自映射到唯一动作', () {
    expect(playerShortcutFor(LogicalKeyboardKey.arrowUp), PlayerShortcut.volumeUp);
    expect(
      playerShortcutFor(LogicalKeyboardKey.arrowDown),
      PlayerShortcut.volumeDown,
    );
    expect(
      playerShortcutFor(LogicalKeyboardKey.arrowLeft),
      PlayerShortcut.seekBack,
    );
    expect(
      playerShortcutFor(LogicalKeyboardKey.arrowRight),
      PlayerShortcut.seekForward,
    );
    expect(playerShortcutFor(LogicalKeyboardKey.keyP), PlayerShortcut.miniWindow);
    expect(
      playerShortcutFor(LogicalKeyboardKey.space),
      PlayerShortcut.togglePlay,
    );
  });

  test('其他键不抢：Esc、Ctrl+K、J/K/L/M 都不属于播放页动作', () {
    for (final key in [
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.keyM,
    ]) {
      expect(playerShortcutFor(key), isNull, reason: '$key 不该被播放页吞掉');
    }
  });

  test('老板键只认 Ctrl+Alt+H，单按 H 或少了修饰键都不触发', () {
    expect(isBossKey(LogicalKeyboardKey.keyH, control: true, alt: true), isTrue);
    expect(isBossKey(LogicalKeyboardKey.keyH, control: true, alt: false), isFalse);
    expect(isBossKey(LogicalKeyboardKey.keyH, control: false, alt: true), isFalse);
    expect(isBossKey(LogicalKeyboardKey.keyH, control: false, alt: false), isFalse);
    expect(
      isBossKey(LogicalKeyboardKey.keyB, control: true, alt: true),
      isFalse,
    );
  });

  test('绑定表恰好六个单键，无修饰键', () {
    final bindings = playerShortcutBindings;
    expect(bindings, hasLength(6));
    for (final activator in bindings.keys) {
      final single = activator as SingleActivator;
      expect(
        single.control || single.alt || single.meta || single.shift,
        isFalse,
        reason: '带修饰键的组合留给 shell 与系统全局热键',
      );
    }
  });
}
