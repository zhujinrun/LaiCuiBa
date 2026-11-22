import 'package:flutter_test/flutter_test.dart';
import 'package:lai_cui_ba/services/danmaku/danmaku_api.dart';
import 'package:lai_cui_ba/services/danmaku/source_danmaku.dart';

import 'support/fake_danmaku.dart';

void main() {
  group('DanmakuService', () {
    late FakeDanmaku fake;

    tearDown(() async => fake.close());

    test('asks by title and episode, then returns that episode', () async {
      fake = await FakeDanmaku.start();
      final service = DanmakuService();
      final out = await service.load(
        title: FakeDanmaku.anime,
        episode: '第3集',
        sources: [fake.source()],
      );
      expect(out.hasContent, isTrue);
      expect(out.episode!.comments, hasLength(3));
      expect(out.episode!.match.episodeId, FakeDanmaku.episodeId);
      // 先按片名+集数搜，命中之后才去取弹幕；没有多余的 /match 请求。
      expect(fake.requests, hasLength(2));
      expect(fake.requests.first, contains('anime=%E4%B8%89%E4%BD%93'));
      expect(fake.requests.first, contains('episode=3'));
    });

    test('the same episode is asked for once', () async {
      fake = await FakeDanmaku.start();
      final service = DanmakuService();
      await service.load(
        title: FakeDanmaku.anime,
        episode: '第3集',
        sources: [fake.source()],
      );
      final before = fake.requests.length;
      final again = await service.load(
        title: FakeDanmaku.anime,
        episode: '第3集',
        sources: [fake.source()],
      );
      expect(again.hasContent, isTrue);
      expect(fake.requests.length, before, reason: '第二次应该命中缓存');
    });

    test('a source with no hit is skipped and the next one answers', () async {
      fake = await FakeDanmaku.start();
      final first = fake.source(id: 'empty', name: '空源');
      fake.matched = false;
      // 同一个服务器冒充两个源：`empty` 搜不到（anime 不匹配时 matched 也关掉了），
      // `second` 是另一个端口上的真源。
      final other = await FakeDanmaku.start();
      addTearDown(other.close);

      final service = DanmakuService();
      final out = await service.load(
        title: FakeDanmaku.anime,
        episode: '第3集',
        sources: [first, other.source(id: 'second', name: '备用源')],
      );
      expect(out.hasContent, isTrue);
      expect(out.episode!.source.id, 'second');
    });

    test('a source that returns no danmaku does not count as a hit', () async {
      fake = await FakeDanmaku.start();
      fake.emptyComments = true;
      final other = await FakeDanmaku.start();
      addTearDown(other.close);

      final service = DanmakuService();
      final out = await service.load(
        title: FakeDanmaku.anime,
        episode: '第3集',
        sources: [fake.source(id: 'empty'), other.source(id: 'second')],
      );
      expect(out.episode!.source.id, 'second');
    });

    test('when every source needs credentials the message says so', () async {
      fake = await FakeDanmaku.start(mode: 'signed');
      final service = DanmakuService();
      final out = await service.load(
        title: FakeDanmaku.anime,
        episode: '第3集',
        sources: [fake.source()],
      );
      expect(out.hasContent, isFalse);
      expect(out.message, contains('AppId/AppSecret'));
    });

    test('no enabled source is a different message from no match', () async {
      fake = await FakeDanmaku.start();
      final service = DanmakuService();
      final none = await service.load(
        title: FakeDanmaku.anime,
        episode: '第3集',
        sources: [fake.source().copyWith(enabled: false)],
      );
      expect(none.message, contains('还没有可用的弹幕源'));

      final noHit = await service.load(
        title: '根本没有这部片',
        episode: '第9集',
        sources: [fake.source()],
      );
      expect(noHit.message, isNot(contains('还没有可用的弹幕源')));
      expect(noHit.hasContent, isFalse);
    });

    test('a label without a number falls back to matching a file name',
        () async {
      fake = await FakeDanmaku.start();
      final service = DanmakuService();
      final out = await service.load(
        title: FakeDanmaku.anime,
        episode: '预告',
        sources: [fake.source()],
      );
      expect(out.hasContent, isTrue);
      // 没有集数就没法按片名搜，只能走 /match。
      expect(fake.requests.first, contains('/api/v2/match'));
    });

    test('clearCache makes the next load ask again', () async {
      fake = await FakeDanmaku.start();
      final service = DanmakuService();
      final sources = [fake.source()];
      await service.load(
        title: FakeDanmaku.anime,
        episode: '第3集',
        sources: sources,
      );
      final before = fake.requests.length;
      service.clearCache();
      await service.load(
        title: FakeDanmaku.anime,
        episode: '第3集',
        sources: sources,
      );
      expect(fake.requests.length, greaterThan(before));
    });
  });

  group('DanmakuSource.parse helpers', () {
    test('enabled defaults to true and survives a round trip', () {
      const s = DanmakuSource(id: 'x', name: 'x');
      final back = DanmakuSource.fromJson(s.toJson())!;
      expect(back.enabled, isTrue);
      expect(back.baseUrl, DanmakuSource.officialBase);
    });
  });
}
