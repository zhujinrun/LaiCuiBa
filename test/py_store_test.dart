import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/py_host.dart';
import 'package:lai_cui_ba/services/script_runtime.dart';
import 'package:lai_cui_ba/services/store.dart';

import 'support/fake_py_host.dart';

/// The store as seen by a TVBox source: a `py` file, a `tvbox` config whose
/// sites are `.py`, and the four questions every page asks (首页 / 搜索 / 详情 /
/// 播放) answered through `TvBoxSource`.
///
/// No interpreter here: [FakePyHost] stands in at the `py_host` protocol seam,
/// which is where the store stops caring how the JSON was produced. The real
/// protocol is covered by `py_host_e2e_test.dart` and `py_runtime_e2e_test.dart`.
void main() {
  late FakePyHost host;
  late FakeScriptSources runtime;
  late AppStore store;

  const film = (
    id: '1001',
    title: '夹具电影',
    playFrom: '线路一\$\$\$线路二',
    playUrl:
        '第1集\$http://a.invalid/1.m3u8#第2集\$http://a.invalid/2.m3u8'
        '\$\$\$第1集\$jx:http://v.qq.com/x',
  );

  String vodRow() => jsonEncode({
    'vod_id': film.id,
    'vod_name': film.title,
    'vod_pic': 'http://example.invalid/m.jpg',
    'vod_remarks': 'HD',
    'vod_year': '2026',
    'vod_content': '这是夹具源，不联网。',
    'vod_play_from': film.playFrom,
    'vod_play_url': film.playUrl,
  });

  setUp(() async {
    host = FakePyHost(
      bodies: {
        'home': (_) => jsonEncode({
          'class': [
            {'type_id': '1', 'type_name': '电影'},
            {'type_id': '2', 'type_name': '剧集'},
          ],
        }),
        'category': (_) => '{"list":[${vodRow()}],"page":1,"pagecount":1}',
        'search': (args) => jsonEncode({
          'list': [
            {
              'vod_id': '2002',
              'vod_name': '搜索:${args.first}',
              'vod_remarks': '严格',
            },
          ],
        }),
        'detail': (_) => '{"list":[${vodRow()}]}',
        'player': (args) {
          final id = '${args[1]}';
          if (id.startsWith('jx:')) {
            return jsonEncode({'parse': 1, 'url': id.substring(3)});
          }
          return jsonEncode({
            'parse': 0,
            'url': 'http://cdn.invalid/real.m3u8',
            'header': {'Referer': 'http://a.invalid/', 'User-Agent': 'LcbTV'},
          });
        },
      },
    );
    runtime = FakeScriptSources(host);
    SharedPreferences.setMockInitialValues({});
    store = await AppStore.load();
    store.scripts = runtime;
  });

  /// One imported `main.py`. Its url is the file itself, and its own id doubles
  /// as the site key (the user never named a site).
  Future<void> addPySource() async {
    await store.addSource(
      const SourceInfo(
        id: 'py-1',
        type: 'py',
        name: '本地 Python 源',
        url: r'D:\sources\main.py',
      ),
    );
    await store.selectSource('py-1');
  }

  group('site resolution', () {
    test('a py source is one site, keyed by the source id', () {
      const source = SourceInfo(
        id: 'py-1',
        type: 'py',
        name: '本地 Python 源',
        url: r'D:\sources\main.py',
      );
      final sites = store.scriptSitesOf(source);
      expect(sites, hasLength(1));
      expect(sites.single.key, 'py-1');
      expect(sites.single.name, '本地 Python 源');
      expect(sites.single.api, r'D:\sources\main.py');
      expect(store.scriptHomeSiteOf(source)?.key, 'py-1');
    });

    test('a config contributes only the sites a script host can run', () {
      const source = SourceInfo(
        id: 'cfg-1',
        type: 'tvbox',
        name: '某个配置',
        url: '',
        homeSite: 'cat',
        sites: [
          SiteInfo(key: 'cat', name: '猫源站点', api: 'https://x.invalid/index.js'),
          SiteInfo(key: 'py-a', name: 'PY 甲', api: 'https://x.invalid/a.py'),
          SiteInfo(key: 'py-b', name: 'PY 乙', api: 'https://x.invalid/b.py'),
          SiteInfo(key: 'js-a', name: 'JS 甲', api: 'https://x.invalid/spider.js'),
        ],
      );
      final sites = store.scriptSitesOf(source);
      // `…/index.js` 是猫源 bundle 的入口，不是单文件 js 站点，所以它留在这里。
      expect(sites.map((s) => s.key).toList(), ['py-a', 'py-b', 'js-a']);
      // homeSite names a cat site, so the first script one takes the front page.
      expect(store.scriptHomeSiteOf(source)?.key, 'py-a');
    });

    test('一个本地 .js 单文件就是一个脚本站点', () {
      const source = SourceInfo(
        id: 'js-1',
        type: 'js',
        name: '本地 js 源',
        url: r'D://src//spider.js',
      );
      final sites = store.scriptSitesOf(source);
      expect(sites, hasLength(1));
      expect(sites.single.key, 'js-1');
      expect(sites.single.api, r'D://src//spider.js');
      expect(store.scriptHomeSiteOf(source)?.key, 'js-1');

      // 一个指向猫源 bundle 的 type=js 源不归脚本宿主管。
      const bundle = SourceInfo(
        id: 'cat-1',
        type: 'js',
        name: '猫源',
        url: 'https://x.invalid/douer/index.js',
      );
      expect(store.scriptSitesOf(bundle), isEmpty);
    });

    test('.js is a script site but …/index.js stays with the 猫源 host', () {
      expect(isJsApi('https://x.invalid/spider.js'), isTrue);
      expect(isJsApi('https://x.invalid/douer/index.js'), isFalse);
      expect(isJsApi(r'D://src//main.js'), isTrue);
      expect(isScriptApi('https://x.invalid/a.py'), isTrue);
      expect(isScriptApi('https://x.invalid/index.js'), isFalse);
      expect(isScriptApi('csp_SomeSite'), isFalse);
    });

    test('a .py with a query string still counts', () {
      const source = SourceInfo(
        id: 'py-2',
        type: 'py',
        name: '带参数',
        url: 'https://x.invalid/main.py?v=2',
      );
      expect(store.scriptSitesOf(source), hasLength(1));
    });

    test('an unrelated source has no Python site', () {
      const mount = SourceInfo(
        id: 'e',
        type: 'emby',
        name: 'Emby',
        url: 'http://192.168.1.2:8096',
      );
      expect(store.scriptSitesOf(mount), isEmpty);
      expect(store.scriptSitesOf(null), isEmpty);
    });
  });

  group('home', () {
    test('a py source answers 首页 with its categories as rails', () async {
      await addPySource();
      expect(store.hasScriptHome, isTrue);
      // It is not a cat source, even though it draws a home screen.
      expect(store.hasSpiderHome, isFalse);
      expect(store.hasMount, isFalse);

      final feed = await store.scriptCatalogue();
      expect(feed, isNotNull);
      expect(feed!.ok, isTrue);
      expect(feed.siteName, '本地 Python 源');
      expect(feed.sections.map((s) => s.title).toList(), ['电影', '剧集']);
      expect(feed.sections.first.items.single.title, '夹具电影');
      // Tagged with the site so detail and play can come back here.
      expect(feed.sections.first.items.single.siteKey, 'py-1');
      expect(feed.hero.first.title, '夹具电影');
    });

    test(
      'a source with no categories says so instead of drawing a blank page',
      () async {
        host = FakePyHost(bodies: {'home': (_) => '{"class":[]}'});
        runtime = FakeScriptSources(host);
        store.scripts = runtime;
        await addPySource();

        final feed = await store.scriptCatalogue();
        expect(feed!.ok, isFalse);
        expect(feed.error, contains('没有返回分类'));
        expect(feed.sections, isEmpty);
      },
    );

    test('no Python runtime means 首页 is not claimed by the source', () async {
      store.scripts = null;
      await store.addSource(
        const SourceInfo(
          id: 'py-1',
          type: 'py',
          name: '本地 Python 源',
          url: r'D:\sources\main.py',
        ),
      );
      await store.selectSource('py-1');
      expect(store.hasScriptHome, isFalse);
      expect(store.scriptCatalogue(), completion(isNull));
    });
  });

  group('search', () {
    test('canSearchReal accepts a py source', () async {
      expect(store.canSearchReal, isFalse);
      await addPySource();
      expect(store.canSearchReal, isTrue);
    });

    test('search streams one group named after the site', () async {
      await addPySource();
      final groups = await store.searchRealStream('流浪地球')!.toList();
      expect(groups, hasLength(1));
      expect(groups.single.site, '本地 Python 源');
      expect(groups.single.items.single.title, '搜索:流浪地球');
      expect(host.calls, contains('search'));
    });

    test('严格 filters a source that matched too loosely', () async {
      await addPySource();
      final groups = await store
          .searchRealStream('别的片', strict: true)!
          .toList();
      // The fake answers with 搜索:别的片, which is not an exact match.
      expect(groups.single.items, isEmpty);
    });

    test(
      'a failing site contributes no group rather than an empty one',
      () async {
        host = FakePyHost(
          bodies: {'search': (_) => throw const PyHostException('站点炸了')},
        );
        runtime = FakeScriptSources(host);
        store.scripts = runtime;
        await addPySource();

        final groups = await store.searchRealStream('随便')!.toList();
        expect(groups, isEmpty);
      },
    );
  });

  group('detail and play', () {
    test(
      'detailReal returns the play lines the source answered with',
      () async {
        await addPySource();
        final full = await store.detailReal(
          const MediaItem(id: '1001', title: '夹具电影', siteKey: 'py-1'),
        );
        expect(full, isNotNull);
        expect(full!.playLines, hasLength(2));
        expect(full.episodes, ['第1集', '第2集']);
        expect(full.siteKey, 'py-1');
        expect(full.overview, '这是夹具源，不联网。');
      },
    );

    test('detailReal reports "no such title" as null', () async {
      host = FakePyHost(bodies: {'detail': (_) => '{"list":[]}'});
      runtime = FakeScriptSources(host);
      store.scripts = runtime;
      await addPySource();
      expect(
        await store.detailReal(const MediaItem(id: 'x', title: '没有')),
        isNull,
      );
    });

    test('playTargetReal asks playerContent and keeps its headers', () async {
      await addPySource();
      const item = MediaItem(
        id: '1001',
        title: '夹具电影',
        siteKey: 'py-1',
        playLines: [
          PlayLine(
            name: '线路一',
            episodes: [
              PlayEpisode(label: '第1集', url: 'http://a.invalid/1.m3u8'),
              PlayEpisode(label: '第2集', url: 'http://a.invalid/2.m3u8'),
            ],
          ),
        ],
      );

      final target = await store.playTargetReal(item, flag: '线路一', nid: 1);
      expect(target, isNotNull);
      expect(target!.url, 'http://cdn.invalid/real.m3u8');
      expect(target.headers['Referer'], 'http://a.invalid/');
      // The episode's own address is what playerContent receives, not the vod id.
      expect(host.lastPlayerArgs?[0], '线路一');
      expect(host.lastPlayerArgs?[1], 'http://a.invalid/2.m3u8');
      // One call answers URL and headers together; asking twice would resolve
      // the source twice.
      expect(host.calls.where((m) => m == 'player'), hasLength(1));
    });

    test('a link that needs a browser parser is not played', () async {
      await addPySource();
      const item = MediaItem(
        id: '1001',
        title: '夹具电影',
        siteKey: 'py-1',
        playLines: [
          PlayLine(
            name: '线路二',
            episodes: [PlayEpisode(label: '第1集', url: 'jx:http://v.qq.com/x')],
          ),
        ],
      );
      expect(await store.playTargetReal(item, flag: '线路二', nid: 0), isNull);
      expect(store.resolvesPlayUrl, isTrue);
    });

    test('an item with no play lines resolves to nothing', () async {
      await addPySource();
      expect(
        await store.playReal(const MediaItem(id: '1', title: '空')),
        isNull,
      );
    });
  });

  group('检测', () {
    test('writes the measured counts back onto the source', () async {
      await addPySource();
      final report = await store.probeSource(store.currentSource!, '');
      expect(report.ok, isTrue);
      expect(report.showCount, 2, reason: '电影 + 剧集');
      expect(report.movieCount, 1);
      expect(report.siteCount, 1);

      final card = store.currentSource!;
      expect(card.movieCount, 1);
      expect(card.showCount, 2);
      expect(card.checkedAt, greaterThan(0));
    });

    test('a source that cannot start keeps its counts at zero', () async {
      store.scripts = null;
      await store.addSource(
        const SourceInfo(
          id: 'py-1',
          type: 'py',
          name: '本地 Python 源',
          url: r'D:\sources\main.py',
        ),
      );
      await store.selectSource('py-1');
      final report = await store.probeSource(store.currentSource!, '');
      // Without a runtime the probe falls through to the cat host, which is
      // also absent: either way the answer names a runtime, not a title count.
      expect(report.ok, isFalse);
      expect(store.currentSource!.movieCount, 0);
    });
  });
}
