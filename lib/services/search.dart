import '../models/models.dart';
import 'demo_data.dart';

/// Search plumbing for the 搜索 page.
///
/// The original fans a keyword out to every site behind the active source and
/// groups what comes back by site ("结果按平台分组"). That fan-out lives in the
/// source layer, which this rebuild has not reached yet, so [searchCatalogue]
/// answers from the bundled demo catalogue and spreads each title across the
/// site names the original returned for the same query. The shapes here are the
/// ones the real implementation needs, so Phase 2 only has to swap the body of
/// [searchCatalogue] for a call into the source.

/// One site's copy of a title.
class SearchHit {
  const SearchHit({
    required this.item,
    required this.site,
    required this.remarks,
  });

  final MediaItem item;

  /// Site name shown in the per-site chip, e.g. 玩偶.
  final String site;

  /// Update note under the title, e.g. 全40集 / 完结.
  final String remarks;
}

/// A site that returned at least one hit, with how many.
class SearchSiteSummary {
  const SearchSiteSummary({required this.site, required this.count});

  final String site;
  final int count;
}

/// Everything the results page needs in one pass.
class SearchOutcome {
  const SearchOutcome({required this.hits, required this.sites});

  /// Grouped by site, then catalogue order inside a site. The original groups
  /// its list the same way, which is why consecutive rows share a chip.
  final List<SearchHit> hits;

  /// Insertion order, matching the order the original lists its chips in.
  final List<SearchSiteSummary> sites;

  int get total => hits.length;

  bool get isEmpty => hits.isEmpty;

  /// How many sites are hidden behind the 还有 N 个站点 tail.
  int overflow(int shown) => sites.length <= shown ? 0 : sites.length - shown;
}

/// Site names read off the original's result chips for 尚公主. Fixture only.
const List<String> demoSites = [
  '玩偶',
  '木偶',
  '闪电',
  '多多',
  '欧歌',
  '花卷',
  '虎斑',
  '小斑',
  '蜗牛',
  '奶西',
  '小猫',
  '泡泡',
];

/// Chips past this index collapse into the 还有 N 个站点 tail, as in the original
/// (eight chips, then the tail).
const int searchSitesShown = 8;

/// Every title the bundled catalogue knows, de-duplicated by title so a show on
/// both the hero carousel and its section does not count twice.
List<MediaItem> get catalogueItems {
  final seen = <String>{};
  final out = <MediaItem>[];
  void add(Iterable<MediaItem> items) {
    for (final item in items) {
      if (seen.add(item.title)) out.add(item);
    }
  }

  add(heroItems);
  for (final section in homeSections) {
    add(section.items);
  }
  add(const [detailDemo]);
  return out;
}

/// FNV-1a over the UTF-16 code units.
///
/// `String.hashCode` is only stable within a single run, and the site spread has
/// to look the same in tests as it does in the app, so the hash is spelled out.
int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Whether [title] belongs on [site]. Deterministic, so the chip counts do not
/// shuffle on every rebuild.
bool _siteCarries(String title, String site) =>
    _stableHash('$title@$site') % 100 < 70;

/// Runs [query] against the catalogue.
///
/// [strict] mirrors the original's 严格 toggle: on, only an exact title matches
/// (15 hits against 75 for the same keyword in the live app); off, any title
/// containing the keyword does.
SearchOutcome searchCatalogue(String query, {bool strict = false}) {
  final needle = query.trim();
  if (needle.isEmpty) {
    return const SearchOutcome(hits: [], sites: []);
  }

  final matched = catalogueItems
      .where(
        (item) =>
            strict ? item.title == needle : item.title.contains(needle),
      )
      .toList(growable: false);
  if (matched.isEmpty) {
    return const SearchOutcome(hits: [], sites: []);
  }

  final hits = <SearchHit>[];
  final sites = <SearchSiteSummary>[];
  for (final site in demoSites) {
    final carried = matched.where((item) => _siteCarries(item.title, site));
    if (carried.isEmpty) continue;
    sites.add(SearchSiteSummary(site: site, count: carried.length));
    for (final item in carried) {
      hits.add(
        SearchHit(
          item: item,
          site: site,
          remarks: item.tag?.isNotEmpty == true ? item.tag! : '完结',
        ),
      );
    }
  }
  return SearchOutcome(hits: hits, sites: sites);
}

/// Suggestions for the drop-down. The original asks a web suggest API; until
/// that exists we offer catalogue titles that contain the query plus a few
/// common suffix words, which is enough to exercise the list.
const List<String> _suggestionSuffixes = [' 演员表', ' 全集', ' 在哪里播', ' 上映'];

List<String> suggestionsFor(String query) {
  final needle = query.trim();
  if (needle.isEmpty) return const [];
  final out = <String>[];
  for (final item in catalogueItems) {
    if (!item.title.contains(needle)) continue;
    out.add(item.title);
    if (out.length >= 6) break;
  }
  for (final suffix in _suggestionSuffixes) {
    if (out.length >= 10) break;
    out.add('$needle$suffix');
  }
  return out;
}
