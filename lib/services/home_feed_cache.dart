import '../models/models.dart';

/// 首页片单的本地缓存，按「源 + 站点」分开存。
///
/// 首页是唯一一个会因为「切走再切回来」而重跑一次源的页面：猫源一回合要走
/// node 子进程，脚本源要跑 Python，慢的时候回到首页就是一片白。原版为此留了
/// `services/home_cache.dart`——先用上次那份把页面铺满，再在后台重取一次。
///
/// 只存源真的答上来的那份（包括「今天没有片单」这种空答案）。失败不缓存，
/// 所以缓存里出现的每一行都是源说过的话，不是占位数据。
class HomeFeedCache {
  final Map<String, _CachedFeed> _feeds = {};

  /// A source alone is not the identity of what 首页 shows: home is drawn from
  /// one site, so the same source can answer with different rails per site.
  static String keyOf(String sourceId, String? siteKey) =>
      '$sourceId|${siteKey ?? ''}';

  /// The rails this source+site answered last time, or null if it never did.
  List<HomeSection>? sectionsOf(String key) => _feeds[key]?.sections;

  /// The site name that came with those rails, for the notice that names who
  /// did not answer this time.
  String siteNameOf(String key) => _feeds[key]?.siteName ?? '';

  /// Remembers a successful answer. A failure must not call this -- an empty
  /// screen is never more informative than the last real片单.
  void put(String key, {required List<HomeSection> sections, String siteName = ''}) {
    _feeds[key] = _CachedFeed(sections, siteName);
  }

  /// Drops everything this source cached, for when it is deleted or its site
  /// list is re-detected and none of the old keys can be reached again.
  void drop(String sourceId) {
    _feeds.removeWhere((key, _) => key.startsWith('$sourceId|'));
  }

  int get length => _feeds.length;
}

class _CachedFeed {
  const _CachedFeed(this.sections, this.siteName);

  final List<HomeSection> sections;
  final String siteName;
}
