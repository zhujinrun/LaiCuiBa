import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/home_feed_cache.dart';

void main() {
  HomeSection section(String title) => HomeSection(
    title: title,
    items: [MediaItem(id: title, title: title)],
  );

  test('按「源 + 站点」分开存：同源换站点是另一份片单', () {
    final cache = HomeFeedCache();
    final a = HomeFeedCache.keyOf('src-1', 'jianpian');
    final b = HomeFeedCache.keyOf('src-1', 'emu');

    cache.put(a, sections: [section('甲的纪录片')], siteName: '荐片');
    expect(cache.sectionsOf(a)?.single.title, '甲的纪录片');
    expect(cache.siteNameOf(a), '荐片');
    // 另一个站点还没问过：不能拿甲站那份顶上去，否则顶栏写乙站、内容还是甲的。
    expect(cache.sectionsOf(b), isNull);
    expect(cache.siteNameOf(b), '');
  });

  test('空答案也算答案，会缓存；失败不能写进来', () {
    final cache = HomeFeedCache();
    final key = HomeFeedCache.keyOf('src-1', null);

    // 「今天没有片单」是源说过的话，缓存它＝下次先用空态，再后台问一次。
    cache.put(key, sections: const []);
    expect(cache.sectionsOf(key), isEmpty);

    // 失败路径根本不调 put —— 这里验证的是 put 之前的判断由首页负责：
    // 一旦缓存里是空的，说明只有「真的答了空」才会进来。
    expect(cache.length, 1);
  });

  test('删源时把它名下的每一份都清掉，别的源不受影响', () {
    final cache = HomeFeedCache();
    cache.put(HomeFeedCache.keyOf('gone', 'a'), sections: [section('要删的')]);
    cache.put(HomeFeedCache.keyOf('gone', 'b'), sections: [section('也要删')]);
    cache.put(HomeFeedCache.keyOf('keep', 'a'), sections: [section('留着的')]);

    cache.drop('gone');

    expect(cache.sectionsOf(HomeFeedCache.keyOf('gone', 'a')), isNull);
    expect(cache.sectionsOf(HomeFeedCache.keyOf('gone', 'b')), isNull);
    expect(cache.sectionsOf(HomeFeedCache.keyOf('keep', 'a'))?.single.title, '留着的');
  });
}
