import '../models/models.dart';
import 'source_catalogue.dart';
import 'spider_client.dart';
import 'tvbox_source.dart';

/// Turns a TVBox (Python) source into the rails the home page draws.
///
/// The shape is deliberately the one [SourceCatalogue] established for 猫源:
/// ask the source what categories it has, fetch the first page of the first few
/// concurrently, drop the ones that came back empty, and say why if none did.
/// The only difference is that a TVBox source already is one site, so there is
/// no candidate hunt — the caller passes the site it chose and this class reads
/// it.
class TvBoxCatalogue {
  const TvBoxCatalogue(this.source, {this.siteName = ''});

  final TvBoxSource source;

  /// The site the rails came from, printed when there are none, so the page can
  /// say 「某某」的分类下没片单 instead of blaming the app.
  final String siteName;

  /// Rails shown, matching [SourceCatalogue.maxSections].
  static const maxSections = 5;

  /// Titles per rail, matching [SourceCatalogue.maxItemsPerSection].
  static const maxItemsPerSection = 24;

  /// A category call that stalls must not hold the front page. Slightly longer
  /// than the 猫源 budget: a TVBox source typically parses an HTML page itself
  /// rather than proxying a worker that already has it.
  static const _pageTimeout = Duration(seconds: 8);

  static const _emptyPage = SpiderList(
    items: [],
    page: 1,
    pageCount: 1,
    total: 0,
  );

  Future<CatalogueFeed> load() async {
    final classes = await _guard(() => source.home(), const <SpiderClass>[]);
    if (classes.isEmpty) {
      return CatalogueFeed.failure('这个源没有返回分类', siteName: siteName);
    }

    final picked = classes.take(maxSections).toList();
    final pages = await Future.wait([
      for (final entry in picked)
        _guard(() => source.category(entry.typeId), _emptyPage),
    ]);

    final sections = <HomeSection>[];
    for (var i = 0; i < picked.length; i++) {
      final items = pages[i].items
          .take(maxItemsPerSection)
          .toList(growable: false);
      if (items.isEmpty) continue;
      sections.add(
        HomeSection(
          title: picked[i].name,
          items: items,
          typeId: picked[i].typeId,
        ),
      );
    }
    if (sections.isEmpty) {
      return CatalogueFeed(
        sections: const [],
        siteName: siteName,
        error: '$siteName 的 ${picked.length} 个分类下暂时没有片单',
      );
    }
    return CatalogueFeed(sections: sections, siteName: siteName);
  }

  /// One dead category must not fail the page; a stall reads as "no data".
  Future<T> _guard<T>(Future<T> Function() body, T fallback) async {
    try {
      return await body().timeout(_pageTimeout);
    } on Object {
      return fallback;
    }
  }
}
