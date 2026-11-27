import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/services/tmdb.dart';
import 'package:lai_cui_ba/services/widgets/widget_models.dart';
import 'package:lai_cui_ba/ui/custom/section_data.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('TMDB 结果按真字段映射，缺图就留空而不是编一张', () {
    final items = TmdbService.parseTrending({
      'results': [
        {
          'id': 123,
          'title': '一部电影',
          'overview': '简介',
          'poster_path': '/abc.webp',
          'release_date': '2024-03-01',
          'vote_average': 8.5,
        },
        {'id': 456, 'name': '没有海报的剧'},
        {'id': null, 'title': '没有 id'},
      ],
    });
    expect(items.length, 2);
    expect(items.first.id, 'tmdb-123');
    expect(items.first.image, '${TmdbService.imageBase}/abc.webp');
    expect(items.first.year, 2024);
    expect(items.first.score, 8.5);
    expect(items.last.image, isNull);
    expect(items.last.tag, 'TMDB');
  });

  test('没有 TMDB Key 时说明原因，不塞假片单', () async {
    final store = await AppStore.load();
    final data = await SectionDataLoader.load(
      store,
      const PageSection(id: 's', source: SectionSource.tmdb),
    );
    expect(data.error, '请先到设置配置 TMDB API Key');
  });

  test('TMDB Key 不进备份', () async {
    final store = await AppStore.load();
    await store.updateSettings(
      store.settings.copyWith(tmdbApiKey: 'secret-key'),
    );
    expect(store.settings.tmdbApiKey, 'secret-key');
    expect(
      store.exportBundle()['settings'].containsKey('tmdbApiKey'),
      isFalse,
    );
  });
}
