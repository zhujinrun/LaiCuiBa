import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/player/boss_key.dart';
import 'package:lai_cui_ba/services/player/keyboard_shortcuts.dart';

/// 键盘链路真实走一遍：焦点落在播放层时方向键命中播放动作，Ctrl+Alt+H
/// 由 shell 层处理。结构对齐 Shell.build：player 是后挂载的覆盖分支。
void main() {
  testWidgets('上下左右命中播放层，不被 shell 层吃掉', (tester) async {
    final hits = <PlayerShortcut>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              // shell 分支先挂载，放空绑定。
              const CallbackShortcuts(
                bindings: {},
                child: SizedBox.expand(),
              ),
              // player 分支后挂载 + autofocus，拿到焦点。
              CallbackShortcuts(
                bindings: {
                  for (final e in playerShortcutBindings.entries)
                    e.key: () => hits.add(e.value),
                },
                child: const Focus(
                  autofocus: true,
                  child: SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    for (final (key, expected) in [
      (LogicalKeyboardKey.arrowUp, PlayerShortcut.volumeUp),
      (LogicalKeyboardKey.arrowDown, PlayerShortcut.volumeDown),
      (LogicalKeyboardKey.arrowLeft, PlayerShortcut.seekBack),
      (LogicalKeyboardKey.arrowRight, PlayerShortcut.seekForward),
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(hits, contains(expected), reason: '$key 应命中 $expected');
    }
    expect(hits, hasLength(4));
  });

  testWidgets('Ctrl+Alt+H 命中 shell 的老板键，不触发播放动作', (tester) async {
    var boss = 0;
    final hits = <PlayerShortcut>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              CallbackShortcuts(
                bindings: {bossKeyActivator: () => boss++},
                child: const Focus(
                  autofocus: true,
                  child: SizedBox.expand(),
                ),
              ),
              CallbackShortcuts(
                bindings: {
                  for (final e in playerShortcutBindings.entries)
                    e.key: () => hits.add(e.value),
                },
                child: const SizedBox.expand(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);

    expect(boss, 1);
    expect(hits, isEmpty, reason: '带修饰键的组合不该落到播放页五个动作');
  });

  test('老板键信号每次 fire 都递增，播放器可据此暂停', () {
    final notifier = BossKeyNotifier();
    var seen = 0;
    notifier.addListener(() => seen = notifier.value);
    notifier.fire();
    notifier.fire();
    expect(seen, 2);
    notifier.dispose();
  });
}
