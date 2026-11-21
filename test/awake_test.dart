import 'package:flutter_test/flutter_test.dart';
import 'package:lai_cui_ba/services/awake.dart';

/// The counting is what keeps a step to the next episode from releasing the
/// lock the new player just took, so it gets its own tests rather than being
/// trusted by inspection.
void main() {
  test('第一次 hold 才真正上锁，最后一次 release 才解开', () async {
    final calls = <bool>[];
    final awake = SystemAwake(toggle: (on) async => calls.add(on));

    await awake.hold();
    await awake.hold();
    expect(calls, [true], reason: '重复 hold 不该重复调平台');

    await awake.release();
    expect(calls, [true], reason: '还有一个持有者，锁不能松');

    await awake.release();
    expect(calls, [true, false]);
    expect(awake.holders, 0);
  });

  test('多余的 release 不会把锁弄反', () async {
    final calls = <bool>[];
    final awake = SystemAwake(toggle: (on) async => calls.add(on));

    await awake.release();
    expect(calls, isEmpty);

    await awake.hold();
    await awake.release();
    await awake.release();
    expect(calls, [true, false]);
  });

  test('平台调用失败不抛出，播放不该因此中断', () async {
    final awake = SystemAwake(toggle: (_) async => throw StateError('no plugin'));

    await expectLater(awake.hold(), completes);
    await expectLater(awake.release(), completes);
    expect(awake.holders, 0);
  });

  test('切集：新的 hold 挡在旧的 release 之前，锁始终没松', () async {
    final calls = <bool>[];
    final awake = SystemAwake(toggle: (on) async => calls.add(on));

    await awake.hold(); // 第 1 集
    await awake.hold(); // 第 2 集先挂载
    await awake.release(); // 第 1 集随后销毁
    expect(calls, [true], reason: '中间不该出现一次 false');
    expect(awake.holders, 1);
  });
}
