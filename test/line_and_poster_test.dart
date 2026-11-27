import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('切换过的线路会被记住，换了顺序也能按名字找回', () async {
    final store = await AppStore.load();
    const item = MediaItem(
      id: 'vod-1',
      title: '尚公主',
      playLines: [
        PlayLine(name: '默认线路'),
        PlayLine(name: 'LZ线路'),
      ],
    );

    expect(store.playLineFor(item), 0);
    await store.savePlayLine(item, 'LZ线路');
    expect(store.playLineFor(item), 1);

    const reordered = MediaItem(
      id: 'vod-1',
      title: '尚公主',
      playLines: [
        PlayLine(name: 'LZ线路'),
        PlayLine(name: '默认线路'),
      ],
    );
    expect(store.playLineFor(reordered), 0);
  });

  test('历史里可用的封面不会被空的详情响应覆盖', () {
    const fromHistory = MediaItem(
      id: 'vod-1',
      title: '尚公主',
      image: 'https://example.com/poster.webp',
      posterSeed: 42,
    );
    const fresh = MediaItem(id: 'vod-1', title: '尚公主');
    final merged = fresh.withPosterFrom(fromHistory);

    expect(merged.image, 'https://example.com/poster.webp');
    expect(merged.posterSeed, 42);
  });
}
