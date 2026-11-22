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

  /// 拿某个作品自己的设置覆盖这一组全局值，逐字段生效。
  ///
  /// 覆盖里为 null 的字段表示"这个字段仍跟着全局走"——所以一部只改过片头的
  /// 剧，片尾用的还是设置页那个值，不会因为改了片头就把片尾清掉。
  SkipRule mergeOverride(SkipOverride? override) {
    if (override == null || override.isEmpty) return this;
    final i = override.introMs;
    final o = override.outroMs;
    return SkipRule(
      intro: i == null ? intro : Duration(milliseconds: i < 0 ? 0 : i),
      outro: o == null ? outro : Duration(milliseconds: o < 0 ? 0 : o),
    );
  }

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
  bool operator ==(Object other) =>
      other is SkipRule && other.intro == intro && other.outro == outro;

  @override
  int get hashCode => Object.hash(intro, outro);

  @override
  String toString() => 'SkipRule(intro: $intro, outro: $outro)';
}

/// 某个作品（一部剧 / 一部电影）单独设的片头片尾。
///
/// 为什么需要它：每部剧的片头长短不一样。设置页那一组是"没单独设过的作品都用
/// 这个"，而一部 90 秒片头的动画和一部 15 秒片头的国产剧混在一起时，只能全局
/// 一个值就一定有一边是错的。这里给每个作品留一组覆盖值。
///
/// 字段为 null 表示该字段**没有覆盖**，仍按全局走；两个都为 null 等于没设过，
/// 存储层会把这条整个删掉，不留空壳。
class SkipOverride {
  const SkipOverride({this.introMs, this.outroMs});

  /// 本剧片头毫秒数。null = 跟随全局。
  final int? introMs;

  /// 本剧片尾毫秒数。null = 跟随全局。
  final int? outroMs;

  static const SkipOverride none = SkipOverride();

  bool get isEmpty => introMs == null && outroMs == null;
  bool get isNotEmpty => !isEmpty;

  /// 只改片头，保留片尾那半边的覆盖状态。
  SkipOverride withIntro(int? ms) => SkipOverride(introMs: ms, outroMs: outroMs);

  /// 只改片尾，保留片头那半边的覆盖状态。
  SkipOverride withOutro(int? ms) =>
      SkipOverride(introMs: introMs, outroMs: ms);

  Map<String, int> toJson() => {
        if (introMs != null) 'intro': introMs!,
        if (outroMs != null) 'outro': outroMs!,
      };

  /// 坏值整条丢：非数字、负数都不认，宁可不覆盖也不要按一个乱数去跳。
  /// 0 是合法值，含义是"这部剧明确没有片头/片尾"，和 null（跟随全局）不同。
  factory SkipOverride.fromJson(Map<String, int> raw) {
    int? pick(String key) {
      final v = raw[key];
      if (v == null || v < 0) return null;
      return v;
    }

    return SkipOverride(introMs: pick('intro'), outroMs: pick('outro'));
  }

  @override
  bool operator ==(Object other) =>
      other is SkipOverride &&
      other.introMs == introMs &&
      other.outroMs == outroMs;

  @override
  int get hashCode => Object.hash(introMs, outroMs);

  @override
  String toString() => 'SkipOverride(intro: $introMs, outro: $outroMs)';
}
