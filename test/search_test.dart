import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/search.dart';

void main() {
  test('loose search groups hits by site and the counts add up', () {
    final outcome = searchCatalogue('尚公主');

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
    final loose = searchCatalogue('现在');
    expect(loose.total, greaterThan(0), reason: 'several titles contain 现在');

    expect(
      searchCatalogue('现在', strict: true).total,
      0,
      reason: 'no title is exactly 现在',
    );

    final exact = searchCatalogue('现在就出发', strict: true);
    expect(exact.total, greaterThan(0));
    expect(exact.hits.every((hit) => hit.item.title == '现在就出发'), isTrue);
  });

  test('an empty query yields nothing', () {
    expect(searchCatalogue('   ').total, 0);
    expect(searchCatalogue('   ').sites, isEmpty);
  });

  test('site spread is stable across runs', () {
    final a = searchCatalogue('尚公主');
    final b = searchCatalogue('尚公主');
    expect(a.total, b.total);
    expect(
      a.sites.map((s) => '${s.site}:${s.count}').toList(),
      b.sites.map((s) => '${s.site}:${s.count}').toList(),
    );
  });

  test('suggestions follow the catalogue then pad with suffix words', () {
    final suggestions = suggestionsFor('尚');
    expect(suggestions.first, '尚公主');
    expect(suggestions.length, lessThanOrEqualTo(10));
    expect(suggestionsFor(''), isEmpty);
  });

  test('overflow reports the sites hidden behind 还有 N 个站点', () {
    final outcome = searchCatalogue('尚公主');
    final shown = outcome.sites.length.clamp(0, searchSitesShown);
    expect(outcome.overflow(searchSitesShown), outcome.sites.length - shown);
  });
}
