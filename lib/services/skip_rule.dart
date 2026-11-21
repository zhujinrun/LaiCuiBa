/// 片头 / 片尾要跳掉多长，由用户自己在设置里定。
///
/// 这不是猜出来的：TVBox 的 `playerContent` 不带片头时间点，猫源的 detail
/// 也不带，所以任何"自动识别片头"的做法都只能靠画面/音频分析——那会误伤正片。
/// 原版的做法就是让用户设两个秒数（片头多久、片尾多久），全站通用；
/// 这里沿用同一条底线，**只有用户显式设过才会跳**，没设就是零，绝不猜。
///
/// 两个护栏都在 [SkipRule] 里，因为它们决定了"这个数值该不该被执行"：
///
/// 1. 单个区间不能超过全片的 40%，
/// 2. 两个区间加起来不能超过一半。
///
/// 越界的唯一解释是设错了（把 90 秒填成 9000，或者拿 3 分钟的短剧套 90 秒片头），
/// 此时宁可什么都不跳，也不要把正片当成片头跳掉。
class SkipRule {
  const SkipRule({this.intro = Duration.zero, this.outro = Duration.zero});

  /// 从每集开头跳过的长度。零表示没设。
  final Duration intro;

  /// 在结尾提前多少算看完。零表示没设。
  final Duration outro;

  /// 关闭自动跳过。
  static const SkipRule none = SkipRule();

  bool get isEmpty => intro <= Duration.zero && outro <= Duration.zero;

  /// 这个规则对该全片时长是否成立。直播（时长为零）永远不成立。
  bool plausibleFor(Duration total) {
    final ms = total.inMilliseconds;
    if (ms <= 0) return false;
    final i = intro.inMilliseconds;
    final o = outro.inMilliseconds;
    if (i < 0 || o < 0) return false;
    if (i + o <= 0) return false;
    // 一秒以下的"片头"只可能是误触，不值得为它跳一下。
    if ((i > 0 && i < 1000) || (o > 0 && o < 1000)) return false;
    // 单值超四成、合计超一半都当误设。用整数比较，避免浮点边界。
    if (i * 5 > ms * 2 || o * 5 > ms * 2) return false;
    if ((i + o) * 2 > ms) return false;
    return true;
  }

  /// 该跳到哪儿作为这一集的开头；null 表示不跳。
  Duration? introFor(Duration total) {
    if (intro <= Duration.zero || !plausibleFor(total)) return null;
    return intro;
  }

  /// 播到这里就算看完；null 表示不判片尾。
  Duration? outroStartFor(Duration total) {
    if (outro <= Duration.zero || !plausibleFor(total)) return null;
    return total - outro;
  }

  @override
  String toString() => 'SkipRule(intro: $intro, outro: $outro)';
}
