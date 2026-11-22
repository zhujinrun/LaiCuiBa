import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/runtime_paths.dart';
import 'package:lai_cui_ba/services/source_catalogue.dart';
import 'package:lai_cui_ba/services/spider_session.dart';
import 'package:lai_cui_ba/services/store.dart';

/// 首页片单：猫源不再只回答搜索/详情/播放，也要回答「首页有什么」。
///
/// 三组测试：hero 挑片规则（纯逻辑）、能进宿主的源判定、以及真起 node.exe +
/// 夹具订阅把 `home`/`category` 变成分区的端到端测试。端到端组缺二进制时跳过。
void main() {
  MediaItem item(String id, {String? image, String? title}) => MediaItem(
    id: id,
    title: title ?? '片$id',
    image: image,
  );

  group('CatalogueFeed.heroOf', () {
    test('dedupes across rails and puts artwork first', () {
      final feed = CatalogueFeed(
        sections: [
          HomeSection(
            title: '电影',
            items: [item('1'), item('2', image: 'https://x/2.jpg')],
          ),
          HomeSection(
            title: '电视剧',
            items: [item('1'), item('3', image: 'https://x/3.jpg')],
          ),
        ],
      );

      // A title filed under two rails is one slide, and a slide with a poster
      // beats a bare record even though it came later.
      expect(
        feed.hero.map((e) => e.id).toList(),
        ['2', '3', '1'],
      );
    });

    test('caps the carousel at five', () {
      final feed = CatalogueFeed(
        sections: [
          HomeSection(
            title: '电影',
            items: [for (var i = 0; i < 8; i++) item('$i')],
          ),
        ],
      );
      expect(feed.hero.length, CatalogueFeed.maxHeroItems);
      expect(feed.hero.first.id, '0');
    });

    test('falls back to title when a record has no id', () {
      final feed = CatalogueFeed(
        sections: [
          HomeSection(
            title: '电影',
            items: [item('', title: '无 id'), item('', title: '无 id')],
          ),
        ],
      );
      expect(feed.hero.length, 1);
    });

    test('empty rails yield no slides, not a placeholder slide', () {
      expect(const CatalogueFeed(sections: []).hero, isEmpty);
    });
  });

  group('hasSpiderHome', () {
    SourceInfo sourceWith({
      String type = 'js',
      String url = 'https://example.test/douer/index.js.md5',
    }) => SourceInfo(id: 'src-home', type: type, name: '测试源', url: url);

    test('a runnable subscription answers the home screen itself', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      final id = await store.addSource(sourceWith());
      await store.selectSource(id);
      expect(store.hasSpiderHome, isTrue);
    });

    test('the shipped default source is one of them', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      // The seeded 豆儿猫源 is a bundle subscription, so the front page will try
      // it on first launch. That is why the page keeps the catalogue until the
      // source answers instead of blanking the screen while it tries.
      expect(store.hasSpiderHome, isTrue);
    });

    test('a config address keeps the bundled catalogue', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      final id = await store.addSource(
        sourceWith(type: 'tvbox', url: 'https://example.test/config.json'),
      );
      await store.selectSource(id);
      // The source cannot boot in the host, so promising it the front page
      // would only turn a working demo screen into a blank one.
      expect(store.hasSpiderHome, isFalse);
    });

    test('mounts are answered by the mount path, not this one', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      final id = await store.addSource(
        sourceWith(type: 'emby', url: 'http://192.168.1.9:8096'),
      );
      await store.selectSource(id);
      expect(store.hasSpiderHome, isFalse);
    });
  });

  final runtime = RuntimePaths.resolve();
  final ready = runtime?.available ?? false;

  group('SourceCatalogue（夹具订阅，真起 node）', () {
    HttpServer? server;
    Directory? root;
    SpiderSession? session;

    setUpAll(() async {
      final rt = runtime!;
      final fixtures = Directory(
        p.join(Directory.current.path, 'test', 'fixtures', 'cat_source'),
      );
      final indexJs = File(p.join(fixtures.path, 'index.js')).readAsBytesSync();
      final configJs = File(
        p.join(fixtures.path, 'index.config.js'),
      ).readAsBytesSync();
      final md5 = crypto.md5.convert(indexJs).toString();

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((request) {
        final response = request.response;
        switch (request.uri.path) {
          case '/index.js.md5':
            response.write(md5);
          case '/index.js':
            response.add(indexJs);
          case '/index.config.js':
            response.add(configJs);
          default:
            response.statusCode = HttpStatus.notFound;
        }
        response.close();
      });

      root = Directory.systemTemp.createTempSync('lcb-catalogue-');
      session = SpiderSession(
        nodePath: rt.node,
        hostScript: rt.hostScript,
        bundleRoot: root!,
      );
    });

    tearDownAll(() async {
      await session?.close();
      await server?.close(force: true);
      if (root != null && root!.existsSync()) root!.deleteSync(recursive: true);
    });

    String subscription() => 'http://127.0.0.1:${server!.port}/index.js.md5';

    SourceInfo sourceWith({
      required String id,
      required List<SiteInfo> sites,
      String homeSite = '',
    }) => SourceInfo(
      id: id,
      type: 'js',
      name: '夹具订阅',
      url: subscription(),
      homeSite: homeSite,
      sites: sites,
    );

    test('turns home categories into rails', () async {
      const site = SiteInfo(key: 'fixture', name: '夹具', type: 'fixture');
      final feed = await SourceCatalogue(session!).load(
        source: sourceWith(
          id: 'fixture-rails',
          homeSite: 'fixture',
          sites: const [site],
        ),
        md5Url: subscription(),
        site: site,
      );

      expect(feed.ok, isTrue, reason: feed.error);
      expect(feed.siteName, '夹具');
      // The fixture declares 电影 + 电视剧 with one title each.
      expect(feed.sections.map((s) => s.title).toList(), ['电影', '电视剧']);
      expect(feed.sections.first.items.single.title, '夹具片甲');
      expect(feed.sections.last.items.single.title, '夹具片乙');
      // Hero is drawn across the rails, deduped.
      expect(feed.hero.map((e) => e.title).toList(), ['夹具片甲', '夹具片乙']);
    });

    test('首页只问选中的那个站点，不去别的站偷内容', () async {
      // 源配置把首页指在死站上，用户在 header 里改成了活站：片单必须来自
      // 活站，而且只能来自活站 —— 页面上顶着哪个站的名字，就得是哪个站的
      // 内容。
      const dead = SiteInfo(key: 'dead', name: '死站', type: 'dead');
      const live = SiteInfo(key: 'fixture', name: '夹具', type: 'fixture');
      final source = sourceWith(
        id: 'fixture-picked',
        homeSite: 'dead',
        sites: const [dead, live],
      );

      final feed = await SourceCatalogue(session!).load(
        source: source,
        md5Url: subscription(),
        site: live,
      );
      expect(feed.ok, isTrue, reason: feed.error);
      expect(feed.siteName, '夹具');
      expect(feed.sections, isNotEmpty);
      expect(feed.sections.first.items.single.siteKey, 'fixture');
    });

    test('选中站点没内容就如实说，不换成别的站', () async {
      // 这是修「换站不更新」时最容易做错的一半：探测别的站能让页面看起来
      // 有内容，但那份内容的站点名和顶栏写的不一样，等于撒谎。
      const dead = SiteInfo(key: 'dead', name: '死站', type: 'dead');
      const live = SiteInfo(key: 'fixture', name: '夹具', type: 'fixture');
      final feed = await SourceCatalogue(session!).load(
        source: sourceWith(
          id: 'fixture-dead',
          homeSite: 'dead',
          sites: const [dead, live],
        ),
        md5Url: subscription(),
        site: dead,
      );

      expect(feed.ok, isFalse);
      expect(feed.siteName, '死站');
      expect(feed.sections, isEmpty);
      // 是「没答上来」，不是「没有推荐内容」——这两句话不是一回事。
      expect(feed.error, contains('首页加载失败'));
      expect(feed.error, contains('死站'));
    });

    test('a source with no enabled site says so without booting', () async {
      final feed = await SourceCatalogue(session!).load(
        source: sourceWith(id: 'fixture-nosite', sites: const []),
        md5Url: subscription(),
      );
      expect(feed.ok, isFalse);
      expect(feed.error, contains('没有可用的站点'));
      expect(feed.sections, isEmpty);
    });
  }, skip: ready ? false : '缺少 assets/runtime/node 时跳过（先跑 tool/sync_runtime.sh）');
}
