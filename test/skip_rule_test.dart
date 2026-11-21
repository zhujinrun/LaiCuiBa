import 'package:flutter_test/flutter_test.dart';
import 'package:lai_cui_ba/services/skip_rule.dart';

/// The rule decides whether a number the viewer typed gets executed, so the
/// guards are the whole point: a wrong value must do nothing, not skip the
/// feature film.
void main() {
  const episode = Duration(minutes: 45);

  group('SkipRule — 何时生效', () {
    test('没设过就什么都不跳', () {
      const rule = SkipRule.none;
      expect(rule.isEmpty, isTrue);
      expect(rule.introFor(episode), isNull);
      expect(rule.outroStartFor(episode), isNull);
      expect(rule.plausibleFor(episode), isFalse);
    });

    test('合理的片头与片尾都生效', () {
      const rule = SkipRule(
        intro: Duration(seconds: 90),
        outro: Duration(seconds: 60),
      );
      expect(rule.introFor(episode), const Duration(seconds: 90));
      expect(rule.outroStartFor(episode), episode - const Duration(seconds: 60));
    });

    test('只设一个时另一个不影响', () {
      const rule = SkipRule(intro: Duration(seconds: 75));
      expect(rule.introFor(episode), const Duration(seconds: 75));
      expect(rule.outroStartFor(episode), isNull);
    });

    test('直播没有总时长，一律不生效', () {
      const rule = SkipRule(intro: Duration(seconds: 90));
      expect(rule.plausibleFor(Duration.zero), isFalse);
      expect(rule.introFor(Duration.zero), isNull);
    });
  });

  group('SkipRule — 误设的护栏', () {
    test('单个区间超过片长四成时拒绝', () {
      // 40 分钟的片子设了 20 分钟片头：这是填错了，不是片头。
      const rule = SkipRule(intro: Duration(minutes: 20));
      expect(rule.introFor(const Duration(minutes: 40)), isNull);
      // 略低于四成仍然可以：15 / 40 = 37.5%。
      const ok = SkipRule(intro: Duration(minutes: 15));
      expect(ok.introFor(const Duration(minutes: 40)), isNotNull);
    });

    test('片头加片尾超过一半时两个都不跳', () {
      // 12 + 12 = 24 分钟，已经超过 45 分钟的一半；单看每个都还在四成内。
      const rule = SkipRule(
        intro: Duration(minutes: 12),
        outro: Duration(minutes: 12),
      );
      expect(rule.introFor(episode), isNull);
      expect(rule.outroStartFor(episode), isNull);
    });

    test('短剧套长片头会被拦下', () {
      // 3 分钟的短剧 + 90 秒片头 = 一半，正是要拦的情形。
      const rule = SkipRule(intro: Duration(seconds: 90));
      expect(rule.introFor(const Duration(minutes: 3)), isNull);
      // 同一规则放在 45 分钟的剧上没问题。
      expect(rule.introFor(episode), isNotNull);
    });

    test('一秒以下当成误触', () {
      const rule = SkipRule(intro: Duration(milliseconds: 800));
      expect(rule.plausibleFor(episode), isFalse);
    });

    test('负数不会反向跳', () {
      const rule = SkipRule(intro: Duration(seconds: -30));
      expect(rule.plausibleFor(episode), isFalse);
    });
  });
}
