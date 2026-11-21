import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/search.dart';

/// The twelve sites 豆儿猫源's config declares, matching what the store seeds.
/// Spelled out here rather than imported so the search tests do not need
/// shared_preferences to run.
///
/// Every case passes `demo: true`: the fixture catalogue is off at runtime, and
/// these cover the matching/grouping rules it still implements for offline
/// layout work. The closing case pins the runtime behaviour instead -- an empty
/// result when the fixtures are off.
const List<SiteInfo> testSites = [
  SiteInfo(key: 'wanou', name: '玩偶'),
  SiteInfo(key: 'muou', name: '木偶'),
  SiteInfo(key: 'shandian', name: '闪电'),
  SiteInfo(key: 'duoduo', name: '多多'),
  SiteInfo(key: 'ouge', name: '欧歌'),
  SiteInfo(key: 'huajuan', name: '花卷'),
  SiteInfo(key: 'huban', name: '虎斑'),
  SiteInfo(key: 'xiaoban', name: '小斑'),
  SiteInfo(key: 'woniu', name: '蜗牛'),
  SiteInfo(key: 'naixi', name: '奶西'),
  SiteInfo(key: 'xiaomao', name: '小猫'),
  SiteInfo(key: 'paopao', name: '泡泡'),
];

void main() {
  test('loose search groups hits by site and the counts add up', () {
    final outcome = searchCatalogue('尚公主', sites: testSites, demo: true);

    expect(outcome.hits, isNotEmpty);
    expect(outcome.sites, isNotEmpty);
    expect(
      outcome.sites.fold<int>(0, (sum, site) => sum + site.count),
      outcome.total,
      reason: 'each site count must equal its rows',
    );

    // Grouped by site: every site's rows form one contiguous run.
    final seen = <String>{};
    String? previous;
    for (final hit in outcome.hits) {
      if (hit.site != previous) {
        expect(
          seen.add(hit.site),
          isTrue,
          reason: 'site ${hit.site} appears in more than one run',
        );
        previous = hit.site;
      }
    }
  });

  test('strict only matches the whole title', () {
    final loose = searchCatalogue('现在', sites: testSites, demo: true);
    expect(loose.total, greaterThan(0), reason: 'several titles contain 现在');

    expect(
      searchCatalogue('现在', sites: testSites, strict: true, demo: true).total,
      0,
      reason: 'no title is exactly 现在',
    );

    final exact = searchCatalogue(
      '现在就出发',
      sites: testSites,
      strict: true,
      demo: true,
    );
    expect(exact.total, greaterThan(0));
    expect(exact.hits.every((hit) => hit.item.title == '现在就出发'), isTrue);
  });

  test('an empty query yields nothing', () {
    expect(searchCatalogue('   ', sites: testSites, demo: true).total, 0);
    expect(searchCatalogue('   ', sites: testSites, demo: true).sites, isEmpty);
  });

  test('site spread is stable across runs', () {
    final a = searchCatalogue('尚公主', sites: testSites, demo: true);
    final b = searchCatalogue('尚公主', sites: testSites, demo: true);
    expect(a.total, b.total);
    expect(
      a.sites.map((s) => '${s.site}:${s.count}').toList(),
      b.sites.map((s) => '${s.site}:${s.count}').toList(),
    );
  });

  test('suggestions follow the catalogue then pad with suffix words', () {
    final suggestions = suggestionsFor('尚', demo: true);
    expect(suggestions.first, '尚公主');
    expect(suggestions.length, lessThanOrEqualTo(10));
    expect(suggestionsFor('', demo: true), isEmpty);
  });

  test('overflow reports the sites hidden behind 还有 N 个站点', () {
    final outcome = searchCatalogue('尚公主', sites: testSites, demo: true);
    final shown = outcome.sites.length.clamp(0, searchSitesShown);
    expect(outcome.overflow(searchSitesShown), outcome.sites.length - shown);
  });

  test('the fan-out covers exactly the sites it is given', () {
    // One site: nothing from the other eleven can leak through.
    final one = searchCatalogue(
      '尚公主',
      sites: const [SiteInfo(key: 'wanou', name: '玩偶')],
      demo: true,
    );
    expect(one.sites.length, lessThanOrEqualTo(1));
    expect(one.hits.every((hit) => hit.site == '玩偶'), isTrue);

    final all = searchCatalogue('尚公主', sites: testSites, demo: true);
    expect(all.total, greaterThan(one.total));

    // No sites at all is the "every source deleted" state, not an empty query:
    // there is nothing to ask, so there is nothing to show.
    expect(searchCatalogue('尚公主', sites: const [], demo: true).total, 0);
  });

  test('with the fixtures off, a query finds nothing on its own', () {
    // The runtime path: no fixtures means the only answer can come from the
    // spider, so the offline call must not invent rows.
    final outcome = searchCatalogue('尚公主', sites: testSites);
    expect(outcome.hits, isEmpty);
    expect(outcome.sites, isEmpty);
    expect(suggestionsFor('尚'), isEmpty);
  });

  test(
    'a silenced site drops out of the fan-out but the rest keep working',
    () {
      final sites = [
        for (final site in testSites)
          site.key == 'wanou' ? site.copyWith(enabled: false) : site,
      ];
      // Search takes the enabled ones, which is what sitesForSelection returns.
      final searchable = sites.where((s) => s.enabled).toList();
      final outcome = searchCatalogue('尚公主', sites: searchable, demo: true);
      expect(outcome.sites.any((s) => s.site == '玩偶'), isFalse);
      expect(outcome.sites, isNotEmpty);
    },
  );
}
