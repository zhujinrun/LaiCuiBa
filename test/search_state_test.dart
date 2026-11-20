import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/core/search_state.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/spider_session.dart';

/// The `submit` behaviour: with a real search wired, the demo catalogue must not
/// flash first (its non-尚公主 rows carry no episodes); the results stay empty
/// until the real search lands, and only fall back to demo when it returns null.
void main() {
  const sites = [
    SiteInfo(key: 'wanou', name: '玩偶', type: '3'),
    SiteInfo(key: 'duoduo', name: '多多', type: '3'),
  ];

  test('no real search: demo answers immediately', () {
    final search = LcbSearch(
      sitesProvider: (_) => sites,
      realSearch: null,
    );
    search.setQuery('尚公主');
    search.submit();

    expect(search.loading, isFalse);
    expect(search.outcome.hits, isNotEmpty);
    expect(search.outcome.hits.first.item.title, '尚公主');
  });

  test('real search returns empty: the results stay empty while loading', () async {
    final search = LcbSearch(
      sitesProvider: (_) => sites,
      realSearch: (keyword, {strict = false}) async {
        // A slow real search that ultimately returns nothing.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return const SpiderSearch(groups: []);
      },
    );
    search.setQuery('尚公主');
    search.submit();

    // The demo catalogue must not win the race: while loading, nothing is shown.
    expect(search.loading, isTrue);
    expect(search.outcome.hits, isEmpty);

    // Once the (empty) real search lands, fall back to the demo catalogue.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(search.loading, isFalse);
    expect(search.outcome.hits, isNotEmpty);
    expect(search.outcome.hits.first.item.title, '尚公主');
  });

  test('real search returns hits: demo is replaced, never shown first', () async {
    final search = LcbSearch(
      sitesProvider: (_) => sites,
      realSearch: (keyword, {strict = false}) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return const SpiderSearch(
          groups: [
            SpiderSearchSite(
              site: '玩偶',
              items: [
                MediaItem(id: '100', title: '庆余年', siteKey: 'wanou'),
              ],
            ),
          ],
        );
      },
    );
    search.setQuery('庆余年');
    search.submit();

    // Real search in flight: nothing from the demo catalogue is shown yet.
    expect(search.loading, isTrue);
    expect(search.outcome.hits, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(search.loading, isFalse);
    expect(search.outcome.hits, hasLength(1));
    expect(search.outcome.hits.first.item.id, '100');
  });
}
