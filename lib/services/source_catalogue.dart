import 'dart:async';

import '../models/models.dart';
import 'spider_session.dart';

/// The home rails a 猫源 answered with.
///
/// `sections` is empty both when the source had nothing to show and when the
/// load failed; [error] is what tells the two apart, so the page can say
/// "这个源的首页取不到片单" instead of drawing an empty library that looks like
/// the user's own.
/// One page of a category, as the grid page needs it.
///
/// [pageCount] is what the source claims, so the page can stop asking instead
/// of scrolling into an endless void; a source that does not say gets one page
/// and no "next" -- claiming more would be a guess.
class CategoryPage {
  const CategoryPage({
    required this.items,
    this.page = 1,
    this.pageCount = 1,
    this.total = 0,
    this.error,
  });

  const CategoryPage.failure(String message)
    : items = const [],
      page = 1,
      pageCount = 1,
      total = 0,
      error = message;

  final List<MediaItem> items;
  final int page;
  final int pageCount;
  final int total;

  /// Why this page is empty, when the app can say something specific.
  final String? error;

  bool get ok => error == null;

  /// Whether asking for [page] + 1 is worth a request.
  bool get hasMore => ok && page < pageCount;
}

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

/// Turns one site's `home` + `category` into the rails the home page draws.
///
/// A mount answers the front page with its own library; a 猫源 has to be asked
/// for its rails. Which site gets asked is the user's choice (`homeSite`), not
/// this class's: drawing from a site the header does not name would put titles
/// on screen that the app credits to somebody else. When the chosen site has
/// nothing, that is the answer -- the original says so and offers another site
/// instead of quietly probing the rest.
class SourceCatalogue {
  const SourceCatalogue(this.session);

  final SpiderSession session;

  /// Rails shown. Sources declare four to ten; two is the smallest seen.
  /// Five is enough for a first screen without paging a site to death.
  static const maxSections = 5;

  /// Titles per rail. The rail scrolls, but a home screen is a sample: fetching
  /// page one is one request, and the poster list only ever shows a handful.
  static const maxItemsPerSection = 24;

  /// The original's wording when a site declares categories but has no feed
  /// behind them -- or declares none at all. The remedy it names is the site
  /// chip, so the page repeats it verbatim.
  static const noContent = '这个站点没有推荐内容，换一个站点试试。';

  /// A stalled site must not hold the front page forever.
  static const timeout = Duration(seconds: 8);

  /// The rails [site] answers with.
  ///
  /// [site] is the site the home header names. Null means the source has no
  /// enabled site at all, which is stated rather than papered over.
  Future<CatalogueFeed> load({
    required SourceInfo source,
    required String md5Url,
    SiteInfo? site,
  }) async {
    final sites = source.searchableSites;
    if (sites.isEmpty) {
      return const CatalogueFeed.failure('这个影视源里没有可用的站点');
    }
    final picked = site ?? sites.first;
    // Reuse a worker that is already up: a home screen is not a 检测, and
    // re-resolving the bundle on every visit would add a download round-trip
    // to the one screen the user sees first.
    final loaded = await session.ensureLoaded(
      id: source.id,
      md5Url: md5Url,
    );
    if (!loaded) {
      return CatalogueFeed.failure(
        session.lastError ?? '源没起来',
        siteName: picked.name,
      );
    }

    // The site's own categories. A timeout here is a failure to answer, not an
    // empty site -- saying "no content" would be a claim we cannot make.
    final home = await _attempt(
      () => session.home(sourceId: source.id, md5Url: md5Url, site: picked),
    );
    final classes = home.value;
    if (classes == null) {
      return CatalogueFeed(
        sections: const [],
        siteName: picked.name,
        error: '首页加载失败：${picked.name} ${home.error ?? '没有答上来'}',
      );
    }
    if (classes.isEmpty) {
      // The site answered; it just has no recommendation to give. That is not
      // a failure to reach it, so it reads as an empty catalogue with the
      // original's advice rather than as an error.
      return CatalogueFeed(
        sections: const [],
        siteName: picked.name,
        note: noContent,
      );
    }

    // Every declared category is asked once, in parallel; the rail that has no
    // titles is dropped rather than shown empty. One dead category must not
    // cost the whole page.
    final rails = classes.take(maxSections).toList();
    final pages = await Future.wait([
      for (final category in rails)
        _attempt(
          () => session.category(
            sourceId: source.id,
            md5Url: md5Url,
            site: picked,
            tid: category.typeId,
          ),
        ),
    ]);

    final sections = <HomeSection>[];
    for (var i = 0; i < rails.length; i++) {
      final page = pages[i].value;
      if (page == null) continue;
      final items = [
        for (final item in page.items.take(maxItemsPerSection))
          // Cards carry the site they came from: the detail page and history
          // rows look the site up by this key, and home used to hand out bare
          // records that claimed no site at all.
          item.withSiteKey(picked.key),
      ];
      if (items.isEmpty) continue;
      sections.add(
        HomeSection(
          title: rails[i].name,
          items: items,
          typeId: rails[i].typeId,
        ),
      );
    }
    if (sections.isEmpty) {
      // 「给了分类但分类下没有片单」is a different sentence from 「没有推荐内容」,
      // and it is the one the user can act on: the site is alive, its feed is
      // dry today.
      return CatalogueFeed(
        sections: const [],
        siteName: picked.name,
        note:
            '${picked.name} 给了 ${classes.length} 个分类，但分类下暂时没有片单',
      );
    }
    return CatalogueFeed(sections: sections, siteName: picked.name);
  }

  /// Runs [body], keeping "it said nothing" apart from "it said nothing yet".
  /// One slow category must not fail the page, but a site that never answers is
  /// a different sentence from a site that has no feed.
  Future<_Attempt<T>> _attempt<T>(Future<T> Function() body) async {
    try {
      return _Attempt.ok(await body().timeout(timeout));
    } on TimeoutException {
      return _Attempt.failed('在 ${timeout.inSeconds} 秒内没有响应');
    } on Object {
      return const _Attempt.failed('请求失败');
    }
  }
}

/// One answer from a site, or the reason there is none.
class _Attempt<T> {
  const _Attempt.ok(this.value) : error = null;
  const _Attempt.failed(this.error) : value = null;

  final T? value;
  final String? error;

  bool get ok => error == null;
}
