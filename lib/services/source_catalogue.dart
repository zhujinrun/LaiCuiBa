import '../models/models.dart';
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
/// Until now the home page only had two answers: a mount's library, or the
/// bundled fixtures. A 猫源 could already be searched, opened and played, but
/// its front page was still demo data -- the last place where "real source" and
/// "what the user sees" disagreed.
class SourceCatalogue {
  const SourceCatalogue(this.session);

  final SpiderSession session;

  /// Rails shown. The fixture declares two; live sources declare four to ten.
  /// Five is enough for a first screen without paging a source to death.
  static const maxSections = 5;

  /// Titles per rail. The rail scrolls, but a home screen is a sample: fetching
  /// page one is one request, and the poster list only ever shows a handful.
  static const maxItemsPerSection = 24;

  /// Sites tried before giving up. `homeSite` goes first (it is the site the
  /// source itself nominates); the rest are fallbacks, because a 猫源 bundles
  /// dozens of sites and the nominated one being dead is normal, not a bug.
  /// Bounded so a source whose every site is dead still fails in seconds.
  static const maxSitesTried = 3;

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
    String? lastNote;
    var declared = 0;

    for (final site in candidates) {
      final classes = await session.home(
        sourceId: source.id,
        md5Url: md5Url,
        site: site,
      );
      if (classes.isEmpty) continue;
      declared = classes.length;

      // One request per rail, all in flight together: a category page is
      // independent of its siblings, and doing them in series would make the
      // first screen take `rails x latency` for no reason. `Future.wait`
      // preserves order, so the rails still follow the source's own.
      final picked = classes.take(maxSections).toList();
      final pages = await Future.wait([
        for (final category in picked)
          session.category(
            sourceId: source.id,
            md5Url: md5Url,
            site: site,
            tid: category.typeId,
          ),
      ]);

      final sections = <HomeSection>[];
      for (var i = 0; i < picked.length; i++) {
        final items = pages[i].items.take(maxItemsPerSection).toList();
        if (items.isEmpty) continue;
        sections.add(HomeSection(title: picked[i].name, items: items));
      }

      if (sections.isNotEmpty) {
        return CatalogueFeed(sections: sections, siteName: site.name);
      }
      // Categories but no titles behind them: worth trying the next site, but
      // remember what happened in case every site answers the same way.
      lastNote =
          '${site.name} 给了 ${classes.length} 个分类，但分类下暂时没有片单';
    }

    if (declared == 0) {
      return CatalogueFeed.failure(
        '首页没有返回分类',
        siteName: candidates.first.name,
      );
    }
    return CatalogueFeed(
      sections: const [],
      siteName: candidates.first.name,
      error: lastNote,
    );
  }

  /// `homeSite` first when it is enabled, then the rest in declaration order.
  List<SiteInfo> _candidates(SourceInfo source, List<SiteInfo> sites) {
    final preferred = <SiteInfo>[];
    final others = <SiteInfo>[];
    for (final site in sites) {
      if (site.key == source.homeSite) {
        preferred.add(site);
      } else {
        others.add(site);
      }
    }
    return [...preferred, ...others].take(maxSitesTried).toList();
  }
}
