import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/py_runtime.dart';
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
      late PyRuntime runtime;

      const source = SourceInfo(id: 'py-1', type: 'py', name: '夹具源', url: '');
      const site = SiteInfo(key: 'py-1', name: '夹具源', api: '');

      setUp(() async {
        cacheDir = await Directory.systemTemp.createTemp('lcb_py_');
        runtime = PyRuntime(
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

  // The same chain the pages use: store → PyRuntime → py_host → fixture. Each
  // piece has its own test; this is the one that proves they are plugged into
  // each other, with no fake anywhere between the page's question and Python.
  group('store + 真 Python 源', () {
    late Directory cacheDir;
    late PyRuntime runtime;
    late AppStore store;

    setUp(() async {
      cacheDir = await Directory.systemTemp.createTemp('lcb_py_store_');
      runtime = PyRuntime(
        pythonPath: paths.python,
        hostScript: paths.hostScript,
        cacheDir: cacheDir,
      );
      SharedPreferences.setMockInitialValues({});
      store = await AppStore.load();
      store.python = runtime;
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
      expect(store.hasPyHome, isTrue);

      final feed = await store.pyCatalogue();
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
  }, skip: ready ? false : '没有 python 运行时（先跑 tool/sync_runtime.sh）');
}
