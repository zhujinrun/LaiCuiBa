import '../models/models.dart';
import 'spider_client.dart';
import 'spider_session.dart';

/// The home rails a 猫源 answered with.
///
/// `sections` is empty both when the source had nothing to show and when the
/// load failed; [error] is what tells the two apart, so the page can say
/// "这个源的首页取不到片单" instead of drawing an empty library that looks like
/// the user's own.
class CatalogueFeed {
  const CatalogueFeed({
    required this.sections,
    this.siteName = '',
    this.error,
    this.note,
  });

  const CatalogueFeed.failure(String message, {this.siteName = ''})
    : sections = const [],
      error = message,
      note = null;

  final List<HomeSection> sections;

  /// The site the rails came from. Home is drawn from one site at a time, so
  /// naming it is the difference between "the app is broken" and "「直」荐片
  /// has no feed today".
  final String siteName;

  /// Why there are no rails. Null when the source answered.
  final String? error;

  /// True but not fatal, e.g. categories came back with no titles behind them.
  final String? note;

  bool get ok => error == null;
  bool get isEmpty => sections.isEmpty;

  /// The hero carousel: the first few titles across the rails.
  ///
  /// Titles with artwork come first -- the hero is a full-bleed backdrop, and a
  /// source that mixes bare records into a populated rail would otherwise put a
  /// grey placeholder where the page's biggest image should be. Order inside
  /// each group is the source's own, so the carousel is stable between opens.
  List<MediaItem> get hero => heroOf(sections);

  /// [hero] for rails that did not come from a [CatalogueFeed] -- namely a
  /// mount's single 影片库 row. Sharing the rule is the point: one home page
  /// should not pick its slides two different ways depending on the source type.
  static List<MediaItem> heroOf(List<HomeSection> sections) {
    final seen = <String>{};
    final all = <MediaItem>[];
    for (final section in sections) {
      for (final item in section.items) {
        final key = item.id.isNotEmpty ? item.id : item.title;
        if (!seen.add(key)) continue;
        all.add(item);
      }
    }
    final withArt = [
      for (final item in all)
        if ((item.image ?? '').isNotEmpty) item,
    ];
    final without = [
      for (final item in all)
        if ((item.image ?? '').isEmpty) item,
    ];
    return [...withArt, ...without].take(maxHeroItems).toList();
  }

  /// The original's hero shows five slides.
  static const maxHeroItems = 5;
}

/// Turns a 猫源's `home` + `category` into the rails the home page draws.
///
/// A mount answers the front page with its own library; a 猫源 has to be asked
/// for its rails. Without this the page had no answer of its own and borrowed
/// fixture data -- the last place where "real source" and "what the user sees"
/// disagreed.
class SourceCatalogue {
  const SourceCatalogue(this.session);

  final SpiderSession session;

  /// Rails shown. Sources declare four to ten; two is the smallest seen.
  /// Five is enough for a first screen without paging a source to death.
  static const maxSections = 5;

  /// Titles per rail. The rail scrolls, but a home screen is a sample: fetching
  /// page one is one request, and the poster list only ever shows a handful.
  static const maxItemsPerSection = 24;

  /// Sites probed before giving up.
  ///
  /// A bundle carries dozens of sites and only some of them answer `category`
  /// at all -- on the default source 19 of 59 do, and the site the source
  /// nominates is not always one of them. Trying three in series therefore
  /// lands on a dead site often, and each dead site costs a full round-trip.
  /// Probing is done in two concurrent rounds instead: every candidate answers
  /// `home` at once, then every live one answers its first category at once.
  /// The cost is two round-trips rather than `sites x latency`.
  static const maxSitesTried = 8;

  /// A site that produced rails once is tried first for the rest of the
  /// process, so revisiting 首页 does not repeat the probe. Not persisted: the
  /// source's own `homeSite` stays the user's choice, and a fresh launch re-asks
  /// -- a site that dies overnight must not be remembered as good.
  static String? _lastGoodSiteKey;

  /// A stalled site must not hold the front page: category calls get a shorter
  /// budget than the client's own timeout, and a timeout counts as "no data".
  static const _probeTimeout = Duration(seconds: 6);

  /// What a failed or stalled category call reads as.
  static const _emptyPage = SpiderList(
    items: [],
    page: 1,
    pageCount: 1,
    total: 0,
  );

  Future<CatalogueFeed> load({
    required SourceInfo source,
    required String md5Url,
  }) async {
    final sites = source.searchableSites;
    if (sites.isEmpty) {
      return const CatalogueFeed.failure('配置里没有启用的站点');
    }
    // Reuse a worker that is already up: a home screen is not a 检测, and
    // re-resolving the bundle on every visit would add a download round-trip
    // to the one screen the user sees first.
    final loaded = await session.ensureLoaded(
      id: source.id,
      md5Url: md5Url,
    );
    if (!loaded) {
      return CatalogueFeed.failure(session.lastError ?? '源没起来');
    }

    final candidates = _candidates(source, sites);

    // Round one: every candidate declares its categories at once.
    final homes = await Future.wait([
      for (final site in candidates)
        _guard(
          () => session.home(
            sourceId: source.id,
            md5Url: md5Url,
            site: site,
          ),
          const <SpiderClass>[],
        ),
    ]);
    final live = <(SiteInfo, List<SpiderClass>)>[];
    for (var i = 0; i < candidates.length; i++) {
      if (homes[i].isNotEmpty) live.add((candidates[i], homes[i]));
    }
    if (live.isEmpty) {
      return CatalogueFeed.failure(
        '首页没有返回分类',
        siteName: candidates.first.name,
      );
    }

    // Round two: each live site answers its first category at once. The first
    // one with titles wins -- a site that declares categories but has no feed
    // behind them is normal, not an error.
    final probes = await Future.wait([
      for (final entry in live)
        _guard(
          () => session.category(
            sourceId: source.id,
            md5Url: md5Url,
            site: entry.$1,
            tid: entry.$2.first.typeId,
          ),
          _emptyPage,
        ),
    ]);
    final hit = probes.indexWhere((page) => page.items.isNotEmpty);
    if (hit < 0) {
      final site = live.first.$1;
      return CatalogueFeed(
        sections: const [],
        siteName: site.name,
        error:
            '${site.name} 给了 ${live.first.$2.length} 个分类，但分类下暂时没有片单',
      );
    }

    final site = live[hit].$1;
    final classes = live[hit].$2;
    _lastGoodSiteKey = site.key;

    // Round three: the remaining rails, in parallel. The category already
    // fetched in round two is reused instead of asked again.
    final picked = classes.take(maxSections).toList();
    final pages = await Future.wait([
      for (var i = 0; i < picked.length; i++)
        if (i == 0)
          Future.value(probes[hit])
        else
          _guard(
            () => session.category(
              sourceId: source.id,
              md5Url: md5Url,
              site: site,
              tid: picked[i].typeId,
            ),
            _emptyPage,
          ),
    ]);

    final sections = <HomeSection>[];
    for (var i = 0; i < picked.length; i++) {
      final items = pages[i].items.take(maxItemsPerSection).toList();
      if (items.isEmpty) continue;
      sections.add(HomeSection(title: picked[i].name, items: items));
    }
    return CatalogueFeed(
      sections: sections,
      siteName: site.name,
      error: sections.isEmpty ? '${site.name} 的分类下暂时没有片单' : null,
    );
  }

  /// Runs [body], turning a stall, a dead worker or a thrown error into
  /// [fallback]: probing a dozen sites must not fail because one of them hangs.
  Future<T> _guard<T>(Future<T> Function() body, T fallback) async {
    try {
      return await body().timeout(_probeTimeout);
    } on Object {
      return fallback;
    }
  }

  /// The site that answered last time, then `homeSite` when it is enabled, then
  /// the rest in declaration order.
  List<SiteInfo> _candidates(SourceInfo source, List<SiteInfo> sites) {
    final remembered = <SiteInfo>[];
    final preferred = <SiteInfo>[];
    final others = <SiteInfo>[];
    for (final site in sites) {
      if (site.key == _lastGoodSiteKey) {
        remembered.add(site);
      } else if (site.key == source.homeSite) {
        preferred.add(site);
      } else {
        others.add(site);
      }
    }
    return [...remembered, ...preferred, ...others].take(maxSitesTried).toList();
  }
}
