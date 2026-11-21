import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/emby_client.dart';
import 'package:lai_cui_ba/services/store.dart';

import 'support/fake_emby.dart';

/// Emby / Jellyfin 挂载：登录换令牌、搜索映射、剧集详情、直链播放地址、检测计数。
///
/// 全部打在一个本地假服务器上（[FakeEmby]），所以不需要真的 Emby 机器，也不会
/// 触碰任何外部源 -- 与这个项目「零外部依赖可自证」的约定一致。
void main() {
  late FakeEmby server;

  setUp(() async {
    server = await FakeEmby.start();
  });

  tearDown(() async {
    await server.close();
  });

  EmbyClient clientFor(String baseUrl) => EmbyClient(
    baseUrl: baseUrl,
    token: FakeEmby.token,
    userId: FakeEmby.userId,
    sourceName: '客厅 Emby',
  );

  group('authenticate', () {
    test('exchanges a password for a token and a user id', () async {
      final auth = await EmbyClient.authenticate(
        baseUrl: server.baseUrl,
        username: 'lxy',
        password: 'secret',
      );

      expect(auth.token, FakeEmby.token);
      expect(auth.userId, FakeEmby.userId);
      expect(auth.serverName, FakeEmby.serverName);
      // The login must identify itself as an Emby client; the server logs the
      // header and the test reads it back.
      expect(server.events.single, contains('MediaBrowser Client="LaiCuiBa"'));
      expect(server.events.single, contains('Device="Windows"'));
    });

    test('a wrong password is a readable error, not a status code', () async {
      await expectLater(
        EmbyClient.authenticate(
          baseUrl: server.baseUrl,
          username: 'lxy',
          password: 'nope',
        ),
        throwsA(
          isA<EmbyException>().having(
            (e) => e.message,
            'message',
            contains('账号或密码不对'),
          ),
        ),
      );
    });

    test('an address with no server behind it says so', () async {
      // Bind then close: the port is known to be free, so the connect is
      // refused immediately instead of waiting out a timeout.
      final probe = await FakeEmby.start();
      final dead = probe.baseUrl;
      await probe.close();

      await expectLater(
        EmbyClient.authenticate(
          baseUrl: dead,
          username: 'lxy',
          password: 'secret',
        ),
        throwsA(
          isA<EmbyException>().having(
            (e) => e.message,
            'message',
            contains('连不上'),
          ),
        ),
      );
    });
  });

  group('search', () {
    test('maps a row onto the card model', () async {
      final client = clientFor(server.baseUrl);
      final items = await client.search('流浪');

      expect(items, hasLength(1));
      final movie = items.single;
      expect(movie.id, 'm1');
      expect(movie.title, '流浪地球');
      expect(movie.year, 2019);
      expect(movie.score, 8.2);
      expect(movie.categories, contains('科幻'));
      // Only actors reach 演员阵容; the director is not cast.
      expect(movie.actors, contains('吴京'));
      expect(movie.actors, isNot(contains('郭帆')));
      expect(movie.area, '中国大陆');
      expect(movie.sourceName, '客厅 Emby');
      // A poster is a URL the server serves, not a bundled asset.
      expect(movie.image, contains('/Items/m1/Images/Primary'));
      expect(movie.image, contains('api_key=${FakeEmby.token}'));
    });

    test('a series is marked so detail knows to fetch episodes', () async {
      final client = clientFor(server.baseUrl);
      final items = await client.search('三体');

      expect(items.single.latest, '全2集');
    });

    test('an empty term lists the whole library', () async {
      final client = clientFor(server.baseUrl);
      final items = await client.search('');

      expect(items.map((e) => e.id), containsAll(['m1', 'm2', 's1']));
    });
  });

  group('detail', () {
    test('a series gets one playable entry per episode', () async {
      final client = clientFor(server.baseUrl);
      final found = (await client.search('三体')).single;
      final detail = await client.detail(found);

      expect(detail.episodes, ['第1集', '第2集']);
      expect(detail.playLines, hasLength(1));
      final line = detail.playLines.single;
      expect(line.name, '直连');
      expect(line.episodes, hasLength(2));
      expect(line.episodes[1].label, '第2集');
      expect(line.episodes[1].url, contains('/Videos/e2/stream'));
      expect(line.episodes[1].url, contains('api_key=${FakeEmby.token}'));
      expect(line.episodes[1].url, contains('static=true'));
      // The row's own fields survive the detail fetch.
      expect(detail.title, '三体');
      expect(detail.image, contains('/Items/s1/Images/Primary'));
    });

    test('a film gets a single 正片 entry', () async {
      final client = clientFor(server.baseUrl);
      final found = (await client.search('流浪')).single;
      final detail = await client.detail(found);

      expect(detail.episodes, isEmpty);
      final episodes = detail.playLines.single.episodes;
      expect(episodes.single.label, '正片');
      expect(episodes.single.url, contains('/Videos/m1/stream'));
    });
  });

  group('probe', () {
    test('reports the library counts and a measured latency', () async {
      final client = clientFor(server.baseUrl);
      final report = await client.probe();

      expect(report.ok, isTrue);
      expect(report.movieCount, 2);
      expect(report.showCount, 1);
      expect(report.latencyMs, greaterThan(0));
      expect(report.usable, isTrue);
    });

    test('a revoked token is reported instead of thrown', () async {
      final client = EmbyClient(
        baseUrl: server.baseUrl,
        token: 'stale',
        userId: FakeEmby.userId,
      );
      final report = await client.probe();

      expect(report.ok, isFalse);
      expect(report.error, contains('登录已失效'));
      expect(report.error, contains('重新添加'));
      expect(report.movieCount, 0);
    });
  });

  group('store routing', () {
    Future<AppStore> storeWithMount() async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      await store.addSource(
        SourceInfo(
          id: 'emby-1',
          type: 'emby',
          name: '客厅 Emby',
          url: server.baseUrl,
          username: 'lxy',
          token: FakeEmby.token,
          tokenUserId: FakeEmby.userId,
        ),
      );
      await store.selectSource('emby-1');
      return store;
    }

    test('a logged-in mount can search, and says so as one site', () async {
      final store = await storeWithMount();
      expect(store.canSearchReal, isTrue);

      final groups = await store
          .searchRealStream('流浪', strict: false)!
          .toList();

      expect(groups, hasLength(1));
      expect(groups.single.site, '客厅 Emby');
      expect(groups.single.items.single.title, '流浪地球');
    });

    test('严格 is applied locally because Emby search is a fuzzy contains',
        () async {
      final store = await storeWithMount();

      // 严格 on: "流浪" is not the title, so nothing comes back -- and an empty
      // group still arrives, so the page does not fall back to demo fixtures
      // and present them as the user's own library.
      final strict = await store
          .searchRealStream('流浪', strict: true)!
          .toList();
      expect(strict, hasLength(1));
      expect(strict.single.items, isEmpty);

      final exact = await store
          .searchRealStream('流浪地球', strict: true)!
          .toList();
      expect(exact.single.items.single.title, '流浪地球');
    });

    test('detail carries the episode URLs the player will use', () async {
      final store = await storeWithMount();
      final groups = await store
          .searchRealStream('三体', strict: false)!
          .toList();
      final found = groups.single.items.single;

      final detail = await store.detailReal(found);
      expect(detail, isNotNull);
      expect(detail!.episodes, ['第1集', '第2集']);
      expect(
        detail.playLines.single.episodes.first.url,
        contains('/Videos/e1/stream'),
      );

      final url = await store.playReal(detail, nid: 1);
      expect(url, contains('/Videos/e2/stream'));
    });

    test('检测 writes the library size onto the source', () async {
      final store = await storeWithMount();
      final source = store.currentSource!;

      final report = await store.probeSource(source, '');

      expect(report.ok, isTrue);
      final updated = store.currentSource!;
      expect(updated.movieCount, 2);
      expect(updated.showCount, 1);
      expect(updated.checkedAt, greaterThan(0));
    });

    test('a mount that never logged in has no client', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      await store.addSource(
        const SourceInfo(
          id: 'emby-2',
          type: 'emby',
          name: '没登录',
          url: 'http://127.0.0.1:1',
        ),
      );
      await store.selectSource('emby-2');

      expect(AppStore.isMountSource(store.currentSource), isTrue);
      expect(store.mountClientOf(store.currentSource), isNull);
      expect(store.canSearchReal, isFalse);
    });
  });
}
