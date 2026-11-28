import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/player/boss_key.dart';
import 'package:lai_cui_ba/services/player/keyboard_shortcuts.dart';

/// 还原 Shell.build 的真实层级：shell 与 player 是 Stack 的两个分支，各自带
/// 一个 Focus。shell 先挂载，player 是「点剧集后」才插入的覆盖层。
///
/// 这个结构是关键：两者同属一个 FocusScope，Flutter 的 autofocus 每个 Scope
/// 只兑现一次 —— shell 先挂已经占掉名额，player 光写 autofocus: true 会被
/// 忽略，焦点留在 shell，方向键一个都到不了播放层。曾因此实测全失效、单测
/// 却全绿（旧测试里 shell 分支没有 autofocus，没还原这个竞争）。
class _PlayerHarness extends StatefulWidget {
  final List<PlayerShortcut> hits;
  final VoidCallback? onBossKey;
  const _PlayerHarness({required this.hits, this.onBossKey});

  @override
  State<_PlayerHarness> createState() => _PlayerHarnessState();
}

class _PlayerHarnessState extends State<_PlayerHarness> {
  bool _open = false;
  final _playerFocus = FocusNode(debugLabel: 'LcbPlayer');

  void _openPlayer() {
    setState(() => _open = true);
    // 和 PlayerPage.initState 一致：等这一帧挂完，显式把焦点抢过来。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playerFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _playerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            // shell 分支：真实 shell.dart 里 CallbackShortcuts > Focus(autofocus)
            CallbackShortcuts(
              bindings: const {},
              child: Focus(
                autofocus: true,
                debugLabel: 'Shell',
                child: Center(
                  child: ElevatedButton(
                    onPressed: _openPlayer,
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
            // player 分支：CallbackShortcuts 在外、Focus 在内。这里必须显式绑
            // FocusNode 并 requestFocus，不能只靠 autofocus（名额被 shell 占了）。
            if (_open)
              CallbackShortcuts(
                bindings: {
                  for (final e in playerShortcutBindings.entries)
                    e.key: () => widget.hits.add(e.value),
                  if (widget.onBossKey != null)
                    bossKeyActivator: widget.onBossKey!,
                },
                child: Focus(
                  focusNode: _playerFocus,
                  debugLabel: 'LcbPlayer',
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('打开播放页后焦点转到 player，上下左右命中播放动作',
      (tester) async {
    final hits = <PlayerShortcut>[];
    await tester.pumpWidget(_PlayerHarness(hits: hits));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Shell');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'LcbPlayer',
      reason: 'player 必须显式抢到焦点，否则方向键到不了绑定',
    );

    for (final (key, expected) in [
      (LogicalKeyboardKey.arrowUp, PlayerShortcut.volumeUp),
      (LogicalKeyboardKey.arrowDown, PlayerShortcut.volumeDown),
      (LogicalKeyboardKey.arrowLeft, PlayerShortcut.seekBack),
      (LogicalKeyboardKey.arrowRight, PlayerShortcut.seekForward),
      (LogicalKeyboardKey.space, PlayerShortcut.togglePlay),
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(hits, contains(expected), reason: '$key 应命中 $expected');
    }
    expect(hits, hasLength(5));
  });

  testWidgets('焦点在播放页时 Ctrl+Alt+H 仍命中老板键，不触发播放动作',
      (tester) async {
    var boss = 0;
    final hits = <PlayerShortcut>[];
    await tester.pumpWidget(_PlayerHarness(
      hits: hits,
      onBossKey: () => boss++,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'LcbPlayer');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);

    expect(boss, 1, reason: '播放页持有焦点时老板键必须照样生效');
    expect(hits, isEmpty, reason: 'Ctrl+Alt+H 不该落到播放页五个动作');
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
