import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/runtime_paths.dart';
import 'package:lai_cui_ba/services/source_probe.dart';
import 'package:lai_cui_ba/services/spider_session.dart';
import 'package:lai_cui_ba/services/store.dart';

/// 可用性度量（检测）：源不是「配置解析成功」就算可用，要真的跑起来读到片单。
///
/// 三组测试分别覆盖：订阅地址判定（纯逻辑）、检测结果写回（持久化）、以及
/// 真起 node.exe + 夹具订阅的端到端检测。端到端组在没有 runtime 二进制时跳过。
void main() {
  SourceInfo sourceWith({
    String type = 'js',
    String url = 'https://example.test/douer/index.js.md5',
    List<SiteInfo> sites = const [],
  }) => SourceInfo(
    id: 'src-probe',
    type: type,
    name: '测试源',
    url: url,
    sites: sites,
  );

  group('spiderAddressOf', () {
    test('accepts the two catvod subscription shapes', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      expect(
        store.spiderAddressOf(sourceWith()),
        'https://example.test/douer/index.js.md5',
      );
      expect(
        store.spiderAddressOf(
          sourceWith(url: 'https://example.test/douer/index.js'),
        ),
        'https://example.test/douer/index.js',
      );
    });

    test('rejects a config address, which is pulled rather than booted', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      expect(
        store.spiderAddressOf(
          sourceWith(type: 'tvbox', url: 'https://example.test/config.json'),
        ),
        isNull,
      );
    });

    test('rejects a local spider file even though it has an address', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      expect(
        store.spiderAddressOf(sourceWith(url: r'E:\films\douer.js')),
        isNull,
      );
    });

    test('rejects mounts and live lists', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      expect(
        store.spiderAddressOf(
          sourceWith(type: 'emby', url: 'http://192.168.1.9:8096'),
        ),
        isNull,
      );
      expect(
        store.spiderAddressOf(
          sourceWith(type: 'live', url: 'https://example.test/live.m3u'),
        ),
        isNull,
      );
    });
  });

  group('applyProbe', () {
    const site = SiteInfo(key: 'fixture', name: '夹具', type: 'fixture');

    test('writes the measured numbers and survives a relaunch', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      final id = await store.addSource(sourceWith(sites: const [site]));

      await store.applyProbe(
        id,
        const ProbeReport(
          latencyMs: 1234,
          movieCount: 58,
          showCount: 4,
          siteCount: 1,
        ),
      );

      final updated = store.sources.firstWhere((s) => s.id == id);
      expect(updated.latencyMs, 1234);
      expect(updated.movieCount, 58);
      expect(updated.showCount, 4);
      expect(updated.checkedAt, greaterThan(0));

      final reloaded = await AppStore.load();
      final restored = reloaded.sources.firstWhere((s) => s.id == id);
      expect(restored.movieCount, 58);
      expect(restored.latencyMs, 1234);
    });

    test('a failed check drops stale counts but keeps the wait', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      final id = await store.addSource(sourceWith(sites: const [site]));
      await store.applyProbe(
        id,
        const ProbeReport(latencyMs: 900, movieCount: 58, showCount: 4),
      );

      await store.applyProbe(
        id,
        const ProbeReport.failure('源没起来', latencyMs: 410),
      );

      final updated = store.sources.firstWhere((s) => s.id == id);
      expect(updated.movieCount, 0);
      expect(updated.showCount, 0);
      expect(updated.latencyMs, 410);
    });
  });

  final runtime = RuntimePaths.resolve();
  final ready = runtime?.available ?? false;

  group('SourceProbe（夹具订阅，真起 node）', () {
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

      // A catvod subscription is just a static directory: `<base>/index.js.md5`
      // names the checksum, `<base>/index.js` and `index.config.js` the bundle.
      // Serving the fixture this way exercises CatBundle for real without
      // touching any commercial source.
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

      root = Directory.systemTemp.createTempSync('lcb-probe-');
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

    test('measures categories and titles from the home screen', () async {
      final url = 'http://127.0.0.1:${server!.port}/index.js.md5';
      final source = SourceInfo(
        id: 'fixture-sub',
        type: 'js',
        name: '夹具订阅',
        url: url,
        homeSite: 'fixture',
        sites: const [SiteInfo(key: 'fixture', name: '夹具', type: 'fixture')],
      );

      final report = await SourceProbe(session!).run(
        source: source,
        md5Url: url,
      );

      expect(report.ok, isTrue, reason: report.error);
      // The fixture declares 电影 + 电视剧 and has exactly two titles.
      expect(report.showCount, 2);
      expect(report.movieCount, 2);
      expect(report.siteCount, 1);
      // Starting node, booting the worker and answering must all be counted.
      expect(report.latencyMs, greaterThan(0));
      expect(report.usable, isTrue);
    });

    test('reports a source with no enabled site instead of booting', () async {
      final report = await SourceProbe(session!).run(
        source: SourceInfo(
          id: 'fixture-empty',
          type: 'js',
          name: '空源',
          url: 'http://127.0.0.1:${server!.port}/index.js.md5',
        ),
        md5Url: 'http://127.0.0.1:${server!.port}/index.js.md5',
      );

      expect(report.ok, isFalse);
      expect(report.error, contains('没有启用的站点'));
    });
  }, skip: ready ? false : '缺少 assets/runtime/node 时跳过（先跑 tool/sync_runtime.sh）');
}
