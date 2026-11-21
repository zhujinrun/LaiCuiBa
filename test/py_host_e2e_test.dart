import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/py_host.dart';
import 'package:lai_cui_ba/services/runtime_paths.dart';
import 'package:lai_cui_ba/services/tvbox_source.dart';

/// Python 宿主（TVBox 源）的端到端测试：真的拉起 `python.exe` + `py_host.py`
/// + 自研夹具源，覆盖行-JSON 协议、`base/spider.py` 契约、代理回传和每次调用
/// 的参数裁剪。
///
/// 和猫源那组一样，它刻意不依赖任何真实商业源 —— 夹具就在
/// `test/fixtures/py_source/main.py`，可以离线、可重复地证明宿主本身是通的。
///
/// 缺少 python 运行时或宿主脚本时整组跳过（先跑 `tool/sync_runtime.sh`）。
void main() {
  final runtime = PyRuntimePaths.resolve();
  final ready = runtime.available;

  group('Python 宿主（夹具源，真起 python）', () {
    const key = 'fixture|py';
    const dartPort = 38123; // 应用侧 /proxy 的端口，只断言握手，不真监听
    PyHost? host;
    late TvBoxSource source;
    late String sourcePath;

    setUpAll(() async {
      sourcePath = File(
        p.join(Directory.current.path, 'test', 'fixtures', 'py_source',
            'main.py'),
      ).absolute.path;
      host = PyHost(
        pythonPath: runtime.python,
        hostScript: runtime.hostScript,
      );
      await host!.start(dartPort: dartPort);
      source = TvBoxSource(host: host!, key: key, path: sourcePath);
    });

    tearDownAll(() async {
      await host?.stop();
    });

    test('宿主应答 ping，报告解释器版本', () {
      expect(host!.isRunning, isTrue);
    });

    test('home 返回分类与筛选', () async {
      final body = await host!.call(
        key: key,
        path: sourcePath,
        method: 'home',
        args: [true],
      );
      final json = jsonDecode(body) as Map<String, dynamic>;
      final classes = json['class'] as List;
      expect(classes.map((c) => c['type_name']).toList(), ['电影', '剧集']);
      expect((json['filters'] as Map).containsKey('1'), isTrue);
    });

    test('category 收到 tid 与页码', () async {
      final body = await host!.call(
        key: key,
        path: sourcePath,
        method: 'category',
        args: ['2', '3', true, <String, dynamic>{}],
      );
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect((json['list'] as List).length, 2);
      expect(json['page'], 3);
      expect(json['pagecount'], 5);
    });

    test('search 把关键词、严格开关和页码都送到源里', () async {
      final body = await host!.call(
        key: key,
        path: sourcePath,
        method: 'search',
        args: ['流浪地球', true, '2'],
      );
      final json = jsonDecode(body) as Map<String, dynamic>;
      final first = (json['list'] as List).first as Map<String, dynamic>;
      expect(first['vod_name'], '搜索:流浪地球');
      expect(first['vod_remarks'], '严格:开');
      expect(json['page'], 2);
    });

    test('detail 原样交回 TVBox 的播放结构', () async {
      final body = await host!.call(
        key: key,
        path: sourcePath,
        method: 'detail',
        args: ['1001'],
      );
      final vod = ((jsonDecode(body) as Map)['list'] as List).first as Map;
      expect(vod['vod_id'], '1001');
      // $$$ 分线路，$ 分集名与地址 —— 解析口径留给 Dart 侧，宿主不碰。
      final from = (vod['vod_play_from'] as String).split(r'$$$');
      final urls = (vod['vod_play_url'] as String).split(r'$$$');
      expect(from, ['线路一', '线路二']);
      expect(urls[0].split('#').length, 2);
      expect(urls[1].split('#').length, 1);
    });

    test('player 回传直链与请求头', () async {
      final body = await host!.call(
        key: key,
        path: sourcePath,
        method: 'player',
        args: ['线路一', 'http://example.invalid/1.m3u8', <String>[]],
      );
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['parse'], 0);
      expect(json['url'], 'http://example.invalid/1.m3u8');
      expect((json['header'] as Map)['User-Agent'], 'LcbFixture');
    });

    test('port 握手：源的 getProxyUrl() 指向应用侧端口', () async {
      final body = await host!.call(
        key: key,
        path: sourcePath,
        method: 'player',
        args: ['线路一', 'x', <String>[]],
      );
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['proxy'], contains('127.0.0.1:$dartPort'));
      expect(json['proxy'], contains('/proxy?do=py'));
    });

    test('proxy 把源的 localProxy 结果带回 Dart（base64 二进制安全）', () async {
      final reply = await host!.proxy({'do': 'py', 'flag': '1'});
      expect(reply.status, 200);
      expect(reply.mime, contains('text/plain'));
      expect(utf8.decode(reply.body), 'proxy:py');
    });

    test('release 之后下一次调用会重新 init', () async {
      await host!.release(key);
      final body = await host!.call(
        key: key,
        path: sourcePath,
        method: 'home',
        args: [true],
      );
      expect((jsonDecode(body) as Map)['class'], isNotEmpty);
    });

    test('源抛异常时错误是源自己的类型与消息', () async {
      final bad = File(
        p.join(Directory.current.path, 'test', 'fixtures', 'py_source',
            'broken.py'),
      ).absolute.path;
      await expectLater(
        host!.call(key: 'broken|py', path: bad, method: 'home', args: [true]),
        throwsA(
          isA<PyHostException>().having(
            (e) => e.message,
            'message',
            contains('RuntimeError'),
          ),
        ),
      );
    });

    // --- TvBoxSource：把宿主交回的原始 JSON 变成模型 --------------------

    test('TvBoxSource.home 出分类', () async {
      final classes = await source.home();
      expect(classes.map((c) => c.name).toList(), ['电影', '剧集']);
      expect(classes.first.typeId, '1');
    });

    test('TvBoxSource.category 把 vod 行映射成 MediaItem', () async {
      final list = await source.category('2', page: '3');
      expect(list.items.length, 2);
      expect(list.page, 3);
      expect(list.pageCount, 5);
      final first = list.items.first;
      expect(first.title, '夹具电影');
      expect(first.image, 'http://example.invalid/movie.jpg');
      expect(first.tag, 'HD');
      expect(first.year, 2026);
    });

    test('TvBoxSource.search 透传关键词与严格开关', () async {
      final list = await source.search('流浪地球', quick: true);
      expect(list.items.first.title, '搜索:流浪地球');
      expect(list.items.first.tag, '严格:开');
    });

    test('TvBoxSource.detail 解析出线路与选集', () async {
      final full = await source.detail(
        const MediaItem(id: '1001', title: '夹具电影'),
      );
      expect(full, isNotNull);
      expect(full!.playLines.length, 2);
      expect(full.playLines.first.name, '线路一');
      expect(full.playLines.first.episodes.length, 2);
      expect(full.playLines.first.episodes.first.label, '第1集');
      expect(
        full.playLines.first.episodes.first.url,
        'http://example.invalid/1.m3u8',
      );
      // 集号列表取自第一条线路，详情页的选集网格就靠它。
      expect(full.episodes, ['第1集', '第2集']);
      expect(full.overview, '这是夹具源，不联网。');
    });

    test('TvBoxSource.detail 对源里没有的 id 返回 null', () async {
      expect(
        await source.detail(const MediaItem(id: 'missing', title: '没有')),
        isNull,
      );
    });

    test('TvBoxSource.play 区分直链与需要解析的链接', () async {
      expect(
        await source.play(flag: '线路一', id: 'http://example.invalid/1.m3u8'),
        'http://example.invalid/1.m3u8',
      );
      // parse=1 是浏览器解析类型，播放器拿不去，如实回 null。
      expect(await source.play(flag: '线路一', id: 'jx:https://v.qq.com/x'), isNull);
      final headers = await source.playHeaders(
        flag: '线路一',
        id: 'http://example.invalid/1.m3u8',
      );
      expect(headers['User-Agent'], 'LcbFixture');
    });

    test('不存在的源文件给的是可读的错误', () async {
      await expectLater(
        host!.call(
          key: 'missing|py',
          path: p.join(Directory.current.path, 'nope', 'main.py'),
          method: 'home',
          args: [true],
        ),
        throwsA(isA<PyHostException>()),
      );
    });
  }, skip: ready ? false : '缺少 python 运行时（先跑 tool/sync_runtime.sh）');
}
