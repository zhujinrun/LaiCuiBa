import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/script_runtime.dart';
import 'package:lai_cui_ba/services/runtime_paths.dart';
import 'package:lai_cui_ba/services/store.dart';

/// The runtime that ties the interpreter, the app-side listener and a source
/// together — with a real `python.exe`, because every interesting part of it is
/// exactly the part a fake would skip: the port handshake, the child process
/// staying up between calls, and a remote api being fetched once.
///
/// Skips itself when the CPython distribution has not been synced (run
/// `tool/sync_runtime.sh`).
void main() {
  final paths = PyRuntimePaths.resolve();
  final ready = paths.available;
  final fixture = File(
    p.join(Directory.current.path, 'test', 'fixtures', 'py_source', 'main.py'),
  ).absolute;

  group(
    'Python 运行时（真起 python）',
    () {
      late Directory cacheDir;
      late ScriptRuntime runtime;

      const source = SourceInfo(id: 'py-1', type: 'py', name: '夹具源', url: '');
      const site = SiteInfo(key: 'py-1', name: '夹具源', api: '');

      setUp(() async {
        cacheDir = await Directory.systemTemp.createTemp('lcb_py_');
        runtime = ScriptRuntime(
          pythonPath: paths.python,
          hostScript: paths.hostScript,
          cacheDir: cacheDir,
        );
      });

      tearDown(() async {
        await runtime.dispose();
        if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
      });

      test('本地 .py 源起得来，代理端口同时就位', () async {
        final client = await runtime.sourceFor(
          source: source,
          site: SiteInfo(key: site.key, name: site.name, api: fixture.path),
        );
        expect(client, isNotNull, reason: runtime.lastError);
        expect(runtime.isRunning, isTrue);
        expect(runtime.port, greaterThan(0));

        final classes = await client!.home();
        expect(classes.map((c) => c.name).toList(), ['电影', '剧集']);
      });

      test('/proxy 把请求送到源的 localProxy，端口就是下发的那个', () async {
        final client = await runtime.sourceFor(
          source: source,
          site: SiteInfo(key: site.key, name: site.name, api: fixture.path),
        );
        expect(client, isNotNull, reason: runtime.lastError);
        // Load the instance first: the proxy looks the source up by siteKey, and
        // a key only exists after init.
        await client!.home();

        final http = HttpClient();
        addTearDown(() => http.close(force: true));
        final request = await http.getUrl(
          Uri.parse(
            'http://127.0.0.1:${runtime.port}/proxy?do=py&siteKey='
            '${Uri.encodeQueryComponent('${source.id}|${site.key}')}',
          ),
        );
        final response = await request.close();
        expect(response.statusCode, 200);
        // The fixture echoes the `do` parameter it received.
        expect(await utf8.decodeStream(response), 'proxy:py');
      });

      test('远端 api 只下载一次，落到 cacheDir 里', () async {
        final body = fixture.readAsBytesSync();
        var hits = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          hits++;
          request.response.headers.contentType = ContentType(
            'text',
            'x-python',
          );
          request.response.add(body);
          await request.response.close();
        });
        final url = 'http://127.0.0.1:${server.port}/main.py';

        final first = await runtime.sourceFor(
          source: source,
          site: SiteInfo(key: site.key, name: site.name, api: url),
        );
        expect(first, isNotNull, reason: runtime.lastError);
        expect(hits, 1);
        final cached = cacheDir.listSync().whereType<File>().toList();
        expect(cached, hasLength(1));
        expect(cached.single.path.endsWith('.py'), isTrue);
        expect(await first!.home(), hasLength(2));

        // A second ask for the same address uses the file on disk.
        final second = await runtime.sourceFor(
          source: source,
          site: SiteInfo(key: site.key, name: site.name, api: url),
        );
        expect(second, isNotNull);
        expect(hits, 1, reason: '第二次不该再发请求');
      });

      test('不存在的源文件给的是可读的错误，不是异常', () async {
        final client = await runtime.sourceFor(
          source: source,
          site: const SiteInfo(
            key: 'py-1',
            name: '夹具源',
            api: r'D:\nope\missing.py',
          ),
        );
        expect(client, isNull);
        expect(runtime.lastError, contains('源文件不存在'));
      });

      test('expandSites 把聚合文件展开成它声明的平台', () async {
        final aggregate = File(
          p.join(Directory.current.path, 'test', 'fixtures', 'py_source',
              'aggregate.py'),
        ).absolute;
        final sites = await runtime.expandSites(
          SourceInfo(id: 'agg-1', type: 'py', name: '聚合源', url: aggregate.path),
        );
        expect(sites, isNotNull, reason: runtime.lastError);
        expect(sites!.map((s) => s.key).toList(), ['alpha', 'beta']);
        expect(sites.map((s) => s.name).toList(), ['甲平台', '乙平台']);
        expect(sites.map((s) => s.api).toSet(), {aggregate.path});

        final alpha = jsonDecode(sites.first.ext) as Map<String, dynamic>;
        expect(alpha['__aggregatePlatform'], 'alpha');
        // SITES 给平台挂的额外参数也要到 ext 里。
        final beta = jsonDecode(sites.last.ext) as Map<String, dynamic>;
        expect(beta['__aggregatePlatform'], 'beta');
        expect(beta['note'], 'beta');
      });

      test('expandSites 对普通源与已展开的站点都不动', () async {
        expect(
          await runtime.expandSites(
            SourceInfo(id: 'py-1', type: 'py', name: '夹具源', url: fixture.path),
          ),
          isNull,
        );
        expect(
          await runtime.expandSites(
            SourceInfo(
              id: 'agg-1',
              type: 'py',
              name: '聚合源',
              url: fixture.path,
              sites: const [
                SiteInfo(
                  key: 'alpha',
                  name: '甲平台',
                  api: '',
                  ext: '{"__aggregatePlatform":"alpha"}',
                ),
              ],
            ),
          ),
          isNull,
        );
      });

      test('dispose 关掉解释器和监听端口', () async {
        await runtime.sourceFor(
          source: source,
          site: SiteInfo(key: site.key, name: site.name, api: fixture.path),
        );
        final port = runtime.port;
        await runtime.dispose();
        expect(runtime.isRunning, isFalse);
        expect(runtime.port, 0);

        final http = HttpClient();
        addTearDown(() => http.close(force: true));
        // Nothing listens on that port any more.
        await expectLater(
          http
              .getUrl(Uri.parse('http://127.0.0.1:$port/cache?do=get&key=x'))
              .then((request) => request.close()),
          throwsA(isA<SocketException>()),
        );
      });
    },
    skip: ready ? false : '没有 python 运行时（先跑 tool/sync_runtime.sh）',
  );

  // The same chain the pages use: store → ScriptRuntime → py_host → fixture. Each
  // piece has its own test; this is the one that proves they are plugged into
  // each other, with no fake anywhere between the page's question and Python.
  group('store + 真 Python 源', () {
    late Directory cacheDir;
    late ScriptRuntime runtime;
    late AppStore store;

    setUp(() async {
      cacheDir = await Directory.systemTemp.createTemp('lcb_py_store_');
      runtime = ScriptRuntime(
        pythonPath: paths.python,
        hostScript: paths.hostScript,
        cacheDir: cacheDir,
      );
      SharedPreferences.setMockInitialValues({});
      store = await AppStore.load();
      store.scripts = runtime;
      await store.addSource(
        SourceInfo(
          id: 'py-1',
          type: 'py',
          name: '夹具源',
          url: fixture.path,
        ),
      );
      await store.selectSource('py-1');
    });

    tearDown(() async {
      await runtime.dispose();
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    });

    test('首页、搜索、详情、播放都走真的 Python 源', () async {
      expect(store.hasScriptHome, isTrue);

      final feed = await store.scriptCatalogue();
      expect(feed, isNotNull, reason: runtime.lastError);
      expect(feed!.sections.first.title, '电影');
      final card = feed.sections.first.items.first;
      expect(card.title, '夹具电影');
      expect(card.siteKey, 'py-1');

      final groups = await store.searchRealStream('流浪地球')!.toList();
      expect(groups, hasLength(1));
      expect(groups.single.site, '夹具源');
      expect(groups.single.items.first.title, '搜索:流浪地球');

      final full = await store.detailReal(card);
      expect(full, isNotNull, reason: runtime.lastError);
      expect(full!.playLines, hasLength(2));
      expect(full.episodes, ['第1集', '第2集']);

      final target = await store.playTargetReal(
        full,
        flag: full.playLines.first.name,
        nid: 1,
      );
      expect(target, isNotNull);
      expect(target!.url, 'http://example.invalid/2.m3u8');
      expect(target.headers['User-Agent'], 'LcbFixture');
    });
    test('检测把聚合源展开成平台，四条链路都落在选中的那个上', () async {
      final aggregate = File(
        p.join(Directory.current.path, 'test', 'fixtures', 'py_source',
            'aggregate.py'),
      ).absolute;
      await store.addSource(
        SourceInfo(id: 'agg-1', type: 'py', name: '聚合源', url: aggregate.path),
      );
      await store.selectSource('agg-1');

      final checked = await store.probeSource(store.currentSource!, '');
      expect(checked.ok, isTrue, reason: checked.error);
      expect(checked.showCount, 1);
      expect(checked.movieCount, 1);

      final expanded = store.currentSource!;
      expect(expanded.sites.map((s) => s.name).toList(), ['甲平台', '乙平台']);
      expect(store.scriptHomeSiteOf(expanded)!.key, 'alpha');

      final feed = await store.scriptCatalogue();
      expect(feed, isNotNull, reason: runtime.lastError);
      expect(feed!.sections.first.title, 'alpha分区');
      final card = feed.sections.first.items.first;
      expect(card.id, 'alpha@@cat');
      expect(card.siteKey, 'alpha');

      final full = await store.detailReal(card);
      expect(full, isNotNull, reason: runtime.lastError);
      expect(full!.title, 'alpha详情');

      final target = await store.playTargetReal(
        full,
        flag: full.playLines.first.name,
        nid: 1,
      );
      expect(target!.url, 'http://example.invalid/alpha/alpha@@cat.m3u8');

      // 再检测一次不会把平台当成文件再展开一遍。
      await store.probeSource(store.currentSource!, '');
      expect(store.currentSource!.sites, hasLength(2));
    });
  }, skip: ready ? false : '没有 python 运行时（先跑 tool/sync_runtime.sh）');

  // The js side, end to end: an `api` that ends in `.js` has to leave the
  // Python runtime, boot `node.exe`, and answer the same four questions. The
  // fixture is a TVBox-style file (synchronous `req` + `pdfh`), so this is the
  // only test that proves the store can tell the two runtimes apart.
  final nodePaths = RuntimePaths.resolve();
  final jsFixture = File(
    p.join(Directory.current.path, 'test', 'fixtures', 'js_source', 'main.js'),
  ).absolute;
  final jsReady =
      nodePaths != null && nodePaths.jsAvailable && jsFixture.existsSync();

  group('store + 真 js 源', () {
    late Directory cacheDir;
    late ScriptRuntime runtime;
    late AppStore store;
    late HttpServer server;
    late String base;

    setUp(() async {
      cacheDir = await Directory.systemTemp.createTemp('lcb_js_store_');
      runtime = ScriptRuntime(
        pythonPath: paths.python,
        hostScript: paths.hostScript,
        cacheDir: cacheDir,
        nodePath: nodePaths!.node,
        jsHostScript: nodePaths.jsSiteHost,
        jsDataDir: p.join(cacheDir.path, 'jsdata'),
      );
      // A small site for the fixture to scrape: the point is that `req` and the
      // selectors really run, not that the JSON was canned.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        switch (request.uri.path) {
          case '/home':
            request.response.write(
              '<html><body><ul class="nav">'
              '<li><a data-id="1" href="/list?tid=1">电影</a></li>'
              '</ul></body></html>',
            );
          case '/list':
            request.response.write(
              '<html><body><div class="item">'
              '<a data-id="101" href="/detail?id=101">三体</a>'
              '<img data-original="http://img.invalid/1.jpg">'
              '<span class="remark">全30集</span></div></body></html>',
            );
          case '/search':
            request.response.write(
              '<html><body><div class="item">'
              '<a data-id="101" href="/detail?id=101">三体</a>'
              '</div></body></html>',
            );
          case '/detail':
            request.response.write(
              '<html><body><h1>三体</h1>'
              '<img class="poster" src="http://img.invalid/p.jpg">'
              '<p class="desc">科幻小说改编</p>'
              '<ul class="eps">'
              '<li><a data-url="http://cdn.invalid/1.m3u8">第1集</a></li>'
              '<li><a data-url="http://cdn.invalid/2.m3u8">第2集</a></li>'
              '</ul></body></html>',
            );
          default:
            request.response.statusCode = 404;
        }
        await request.response.close();
      });

      SharedPreferences.setMockInitialValues({});
      store = await AppStore.load();
      store.scripts = runtime;
      await store.addSource(
        SourceInfo(
          id: 'js-1',
          type: 'tvbox',
          name: '配置源',
          url: '',
          sites: [
            SiteInfo(key: 'js-a', name: 'JS 甲', api: jsFixture.path, ext: base),
          ],
        ),
      );
      await store.selectSource('js-1');
    });

    tearDown(() async {
      await runtime.dispose();
      await server.close(force: true);
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    });

    test('首页、搜索、详情、播放都走真的 node + 夹具 js 源', () async {
      expect(store.hasScriptHome, isTrue);
      expect(store.resolvesPlayUrl, isTrue);

      final feed = await store.scriptCatalogue();
      expect(feed, isNotNull, reason: runtime.lastError);
      expect(feed!.sections.first.title, '电影');
      final card = feed.sections.first.items.first;
      expect(card.title, '三体');
      expect(card.siteKey, 'js-a');

      final groups = await store.searchRealStream('三体')!.toList();
      expect(groups, hasLength(1));
      expect(groups.single.site, 'JS 甲');
      expect(groups.single.items.first.title, '三体');

      final full = await store.detailReal(card);
      expect(full, isNotNull, reason: runtime.lastError);
      expect(full!.title, '三体');
      expect(full.episodes, ['第1集', '第2集']);

      final target = await store.playTargetReal(
        full,
        flag: full.playLines.first.name,
        nid: 1,
      );
      expect(target, isNotNull);
      expect(target!.url, endsWith('.m3u8'));
      expect(target.headers['Referer'], '$base/');
    });

    test('没有 Node 运行时的时候，js 站点说的是缺什么', () async {
      final pyOnly = ScriptRuntime(
        pythonPath: paths.python,
        hostScript: paths.hostScript,
        cacheDir: cacheDir,
      );
      addTearDown(pyOnly.dispose);
      final client = await pyOnly.sourceFor(
        source: const SourceInfo(id: 'js-1', type: 'tvbox', name: '配置源', url: ''),
        site: SiteInfo(key: 'js-a', name: 'JS 甲', api: jsFixture.path),
      );
      expect(client, isNull);
      expect(pyOnly.lastError, contains('js'));
      expect(pyOnly.lastError, contains('Node'));
    });
  }, skip: jsReady ? false : '缺少 node 运行时（先跑 tool/sync_runtime.sh）');
}
