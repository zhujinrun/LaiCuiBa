import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/core/search_state.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/spider_session.dart';

/// The `submit` behaviour: results appear site by site as each stream event
/// lands. Nothing is filled in from the bundled fixtures -- they are off at
/// runtime -- so a search that reaches no site reports that rather than showing
/// sample rows.
void main() {
  const sites = [
    SiteInfo(key: 'wanou', name: '玩偶', type: '3'),
    SiteInfo(key: 'duoduo', name: '多多', type: '3'),
  ];

  test('no real search: the query stays on the machine and says so', () {
    final search = LcbSearch(
      sitesProvider: (_) => sites,
      realSearchStream: null,
    );
    // 严格 defaults on.
    expect(search.strict, isTrue);
    expect(search.canSearch, isFalse);

    search.setQuery('尚公主');
    search.submit();

    // No runtime means no site was asked. An empty result here is the honest
    // answer; the page reads [canSearch] and blames the missing component
    // rather than the sites.
    expect(search.loading, isFalse);
    expect(search.outcome.hits, isEmpty);
    expect(search.outcome.sites, isEmpty);
  });

  test('strict defaults on and toggleExpanded flips the chip row', () {
    final search = LcbSearch(
      sitesProvider: (_) => sites,
      realSearchStream: null,
    );

    expect(search.strict, isTrue);
    search.toggleStrict();
    expect(search.strict, isFalse);

    expect(search.expanded, isFalse);
    search.toggleExpanded();
    expect(search.expanded, isTrue);
    search.toggleExpanded();
    expect(search.expanded, isFalse);
  });

  test('real search emits nothing: the page ends up with no results', () async {
    final search = LcbSearch(
      sitesProvider: (_) => sites,
      realSearchStream: (keyword, {strict = false}) async* {
        // A slow real search that ultimately emits no site.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
    );
    search.setQuery('尚公主');
    search.submit();

    // Nothing placeholder-shaped wins the race: while loading, nothing is shown.
    expect(search.loading, isTrue);
    expect(search.outcome.hits, isEmpty);

    // The sites answered with nothing, and that is what the page keeps.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(search.loading, isFalse);
    expect(search.outcome.hits, isEmpty);
  });

  test('real search streams hits: appended site by site', () async {
    final search = LcbSearch(
      sitesProvider: (_) => sites,
      realSearchStream: (keyword, {strict = false}) async* {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        yield const SpiderSearchSite(
          site: '玩偶',
          items: [
            MediaItem(id: '100', title: '庆余年', siteKey: 'wanou'),
          ],
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        yield const SpiderSearchSite(
          site: '多多',
          items: [
            MediaItem(id: '200', title: '狂飙', siteKey: 'duoduo'),
          ],
        );
      },
    );
    search.setQuery('庆余年');
    search.submit();

    // Real search in flight: nothing from the demo catalogue is shown yet.
    expect(search.loading, isTrue);
    expect(search.outcome.hits, isEmpty);

    // The first site lands and is shown immediately, still loading the rest.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(search.loading, isFalse);
    expect(search.outcome.hits, hasLength(1));
    expect(search.outcome.hits.first.item.id, '100');

    // The second site appends.
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(search.outcome.hits, hasLength(2));
    expect(search.outcome.sites, hasLength(2));
  });
}
