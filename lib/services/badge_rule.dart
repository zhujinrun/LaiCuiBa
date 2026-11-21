/// 媒体规格徽章：从片名 / 备注里识别「4K、HDR10、杜比视界、DTS…」这类规格，
/// 供海报角落渲染。
///
/// 与原版 `BadgeRule` 同一思路——用正则从文本里抓规格关键词。数据来源是
/// catvod/TVBox 的 `vod_name`（片名）与 `vod_remarks`（备注），中文源通常不给
/// 英文规格后缀，所以识别不到就什么都不显示，绝不回落 demo。
///
/// 纯逻辑、无 IO，便于单测；渲染层的取舍（要不要文字、摆哪个角、关掉哪些
/// 规格）交给 `AppSettings` 与 `ui/widgets/media_badges.dart`，这里只负责
/// 「这段文本里到底有哪些规格」这一个判断。
library;

/// 一类规格，含机器可读的 [slug] 和给人看的中文 [label]。
///
/// [group] 只用于渲染时的配色分组，不参与识别。
enum BadgeGroup { quality, hdr, audio, source }

class MediaBadge {
  const MediaBadge._(this.slug, this.label, this.short, this.group);

  /// 机器键，与设置里「关掉哪一类」的开关一一对应。
  final String slug;

  /// 完整中文名，如「杜比视界」。
  final String label;

  /// 短标，如「4K」「DV」。
  final String short;

  final BadgeGroup group;

  @override
  bool operator ==(Object other) =>
      other is MediaBadge && other.slug == slug;

  @override
  int get hashCode => slug.hashCode;

  @override
  String toString() => label;
}

/// 识别规则表：按「越具体越优先」排序，先命中的先放进结果。
///
/// 每条的 [pattern] 是对**小写化**文本做的不区分大小写正则（含词边界由
/// [word] 控制），[test] 在命中后决定取哪一个徽章（例如 `dolby vision` 与
/// `dolby digital` 都含 `dolby`，靠更长的先匹配来区分）。
class BadgeRule {
  BadgeRule._();

  /// 全部可识别的规格。识别顺序由 [_patterns] 与分辨率互斥规则决定，
  /// 渲染顺序由 [_groupOrder] 分组再排。
  static const all = <MediaBadge>[
    MediaBadge._('dolbyVision', '杜比视界', 'DV', BadgeGroup.hdr),
    MediaBadge._('hdr10plus', 'HDR10+', 'HDR10+', BadgeGroup.hdr),
    MediaBadge._('hdr10', 'HDR10', 'HDR10', BadgeGroup.hdr),
    MediaBadge._('hdr', 'HDR', 'HDR', BadgeGroup.hdr),
    MediaBadge._('atmos', '杜比全景声', 'Atmos', BadgeGroup.audio),
    MediaBadge._('truehd', 'TrueHD', 'TrueHD', BadgeGroup.audio),
    MediaBadge._('dtsx', 'DTS:X', 'DTS:X', BadgeGroup.audio),
    MediaBadge._('dtshd', 'DTS-HD', 'DTS-HD', BadgeGroup.audio),
    MediaBadge._('dts', 'DTS', 'DTS', BadgeGroup.audio),
    MediaBadge._('dolbyDigital', '杜比数字', 'DD', BadgeGroup.audio),
    MediaBadge._('uhd', '4K', '4K', BadgeGroup.quality),
    MediaBadge._('q8k', '8K', '8K', BadgeGroup.quality),
    MediaBadge._('q2160', '2160p', '2160p', BadgeGroup.quality),
    MediaBadge._('q1080', '1080p', '1080p', BadgeGroup.quality),
    MediaBadge._('q720', '720p', '720p', BadgeGroup.quality),
    MediaBadge._('hevc', 'HEVC', 'HEVC', BadgeGroup.quality),
    MediaBadge._('imax', 'IMAX', 'IMAX', BadgeGroup.source),
    MediaBadge._('remux', 'Remux', 'Remux', BadgeGroup.source),
    MediaBadge._('bluray', 'BluRay', 'BD', BadgeGroup.source),
    MediaBadge._('webdl', 'WEB-DL', 'WEB-DL', BadgeGroup.source),
  ];

  /// 渲染顺序：画质在前，HDR 其次，再音轨，最后来源。
  static const _groupOrder = <BadgeGroup, int>{
    BadgeGroup.quality: 0,
    BadgeGroup.hdr: 1,
    BadgeGroup.audio: 2,
    BadgeGroup.source: 3,
  };

  /// 每种规格的识别正则（小写化文本上跑）。次序上更具体的（`hdr10+`）排在
  /// 通用的（`hdr`）之前，先到先得；`hdr10` 命中的就不该再被 `hdr` 重复抓。
  static const _patterns = <String, String>{
    'dolbyVision': r'\b(dolby\s?vision|dovi|\bdv\b)\b',
    'hdr10plus': r'\bhdr\s?10\s?\+',
    'hdr10': r'\bhdr\s?10(?!\s?\+)\b',
    'hdr': r'\bhdr\b',
    'atmos': r'\batmos\b',
    'truehd': r'\btrue\s?hd\b',
    'dtsx': r'\bdts\s?:?\s?x\b',
    'dtshd': r'\bdts\s?-?\s?hd',
    'dts': r'\bdts\b',
    'dolbyDigital': r'\b(dolby\s?digital|ddp?\d?(\.\d)?|e?ac3)\b',
    'uhd': r'\b(4k|uhd|2160p|3840\s?x\s?2160)\b',
    'q8k': r'\b(8k|4320p|7680\s?x\s?4320)\b',
    'q2160': r'\b2160p\b',
    'q1080': r'\b1080[pi]\b',
    'q720': r'\b720p\b',
    'hevc': r'\b(x265|h\.?265|hevc)\b',
    'imax': r'\bimax\b',
    'remux': r'\bremux\b',
    'bluray': r'\b(blu\s?-?\s?ray|bdrip|brrip|bluray)\b',
    'webdl': r'\b(web[- .]?dl|webrip|web)\b',
  };

  /// 从标题、备注等文本里识别出的规格徽章，按画质 → HDR → 音轨 → 来源排序。
  ///
  /// 输入是原始大小写，内部统一转小写再匹配，所以 `HDR10`、`hdr10` 都命中。
  /// 空文本返回空列表——中文片名没有规格后缀时就是这样。
  static List<MediaBadge> badgesOf(
    String title, {
    String? remarks,
    String? tag,
  }) {
    final text = [title, remarks, tag]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' ')
        .toLowerCase();
    if (text.isEmpty) return const [];

    final out = <MediaBadge>[];
    for (final badge in all) {
      final pattern = _patterns[badge.slug];
      if (pattern == null) continue;
      if (!RegExp(pattern).hasMatch(text)) continue;
      // 分辨率三档互斥：已经命中更高一档就跳过低的，避免「2160p」既给 4K
      // 又给 2160p。
      if (badge.slug == 'q2160' && _has(out, 'uhd')) continue;
      if (badge.slug == 'q1080' && _hasAny(out, ['uhd', 'q2160'])) continue;
      if (badge.slug == 'q720' && _hasAny(out, ['uhd', 'q2160', 'q1080'])) {
        continue;
      }
      // `hdr` 是兜底：只要出现了更具体的 hdr10/hdr10+ 就不再重复给一个泛泛的
      // HDR。
      if (badge.slug == 'hdr' && _hasAny(out, ['hdr10', 'hdr10plus'])) {
        continue;
      }
      out.add(badge);
    }
    out.sort((a, b) =>
        _groupOrder[a.group]!.compareTo(_groupOrder[b.group]!));
    return out;
  }

  static bool _has(List<MediaBadge> list, String slug) =>
      list.any((b) => b.slug == slug);

  static bool _hasAny(List<MediaBadge> list, List<String> slugs) =>
      list.any((b) => slugs.contains(b.slug));
}
