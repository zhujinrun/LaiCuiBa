import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/core/search_state.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/spider_session.dart';

/// The `submit` behaviour: with a real search wired, the demo catalogue must not
/// flash first (its non-尚公主 rows carry no episodes); results appear site by
/// site as each stream event lands, and only fall back to demo when every site
/// comes back empty.
void main() {
  const sites = [
    SiteInfo(key: 'wanou', name: '玩偶', type: '3'),
    SiteInfo(key: 'duoduo', name: '多多', type: '3'),
  ];

  test('no real search: demo answers immediately', () {
    final search = LcbSearch(
      sitesProvider: (_) => sites,
      realSearchStream: null,
    );
    search.setQuery('尚公主');
    search.submit();

    expect(search.loading, isFalse);
    expect(search.outcome.hits, isNotEmpty);
    expect(search.outcome.hits.first.item.title, '尚公主');
  });

  test('real search emits nothing: fall back to demo when done', () async {
    final search = LcbSearch(
      sitesProvider: (_) => sites,
      realSearchStream: (keyword, {strict = false}) async* {
        // A slow real search that ultimately emits no site.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
    );
    search.setQuery('尚公主');
    search.submit();

    // The demo catalogue must not win the race: while loading, nothing is shown.
    expect(search.loading, isTrue);
    expect(search.outcome.hits, isEmpty);

    // Once the (empty) real search closes, fall back to the demo catalogue.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(search.loading, isFalse);
    expect(search.outcome.hits, isNotEmpty);
    expect(search.outcome.hits.first.item.title, '尚公主');
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
