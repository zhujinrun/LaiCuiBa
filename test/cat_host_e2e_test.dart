import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:lai_cui_ba/services/cat_host.dart';
import 'package:lai_cui_ba/services/runtime_paths.dart';
import 'package:lai_cui_ba/services/spider_client.dart';

/// 猫源宿主的端到端测试：真的拉起 `node.exe` + `cat_host.js` + 自研夹具源，
/// 覆盖 Dart 侧 [CatHost] / [SpiderClient] 的完整链路。
///
/// 它刻意不依赖任何真实商业源——夹具就在 `test/fixtures/cat_source`，
/// 所以这个测试可以离线、可重复地证明「宿主本身是通的」。
///
/// 缺少 node.exe / cat_host.js 时整组跳过（先跑 `tool/sync_runtime.sh`）。
void main() {
  final runtime = RuntimePaths.resolve();
  final ready = runtime?.available ?? false;

  group('猫源宿主（夹具源，真起 node）', () {
    CatHost? host;
    SpiderClient? client;
    Directory? fixture;

    setUpAll(() async {
      final rt = runtime!;
      // 宿主会把源的库写到 bundle 的 data/ 下；拷到临时目录，别污染仓库。
      fixture = Directory.systemTemp.createTempSync('lcb-fixture-');
      final src = Directory(
        p.join(Directory.current.path, 'test', 'fixtures', 'cat_source'),
      );
      for (final name in ['index.js', 'index.config.js']) {
        File(p.join(src.path, name)).copySync(p.join(fixture!.path, name));
      }

      host = CatHost(nodePath: rt.node, hostScript: rt.hostScript);
      final control = await host!.start();
      expect(control, greaterThan(0));
      final sourcePort = await host!.loadSource('fixture', fixture!.path);
      expect(sourcePort, greaterThan(0));
      client = SpiderClient(sourcePort);
    });

    tearDownAll(() async {
      await host?.stop();
      try {
        fixture?.deleteSync(recursive: true);
      } on Object {
        // 临时目录清理是尽力而为。
      }
    });

    test('home 返回站点分类', () async {
      final classes = await client!.home('fixture', 'fixture');
      expect(classes.map((c) => c.name).toList(), ['电影', '电视剧']);
    });

    test('search 把 vod 行映射成 MediaItem', () async {
      final list = await client!.search('fixture', 'fixture', '夹具');
      expect(list.items, hasLength(2));

      final first = list.items.firstWhere((i) => i.id == '101');
      expect(first.title, '夹具片甲');
      expect(first.year, 2026);
      expect(first.area, '中国大陆');
      expect(first.categories, ['电影']);
      expect(first.actors, ['演员甲', '演员乙']);
    });

    test('detail 解析出线路与选集', () async {
      final item = await client!.detail('fixture', 'fixture', '102');
      expect(item, isNotNull);
      expect(item!.title, '夹具片乙');
      expect(item.playLines, hasLength(1));
      expect(
        item.playLines.first.episodes.map((e) => e.label).toList(),
        ['第1集', '第2集'],
      );
      expect(
        item.episodes,
        ['第1集', '第2集'],
      );
    });

    test('play 按 nid 取到对应集', () async {
      final ep0 = await client!.play('fixture', 'fixture', '102', nid: 0);
      final ep1 = await client!.play('fixture', 'fixture', '102', nid: 1);
      expect(ep0, endsWith('/b1.m3u8'));
      expect(ep1, endsWith('/b2.m3u8'));
    });

    test('未知站点返回空结果而不是抛异常', () async {
      final list = await client!.search('nope', 'fixture', '夹具');
      expect(list.items, isEmpty);
    });

    test('卸载源后端口不再可用', () async {
      // 用独立的 host 验证卸载语义，避免影响上面共享的那份。
      final rt = runtime!;
      final solo = CatHost(nodePath: rt.node, hostScript: rt.hostScript);
      try {
        await solo.start();
        final port = await solo.loadSource('fixture', fixture!.path);
        final probe = SpiderClient(port);
        final before = await probe.home('fixture', 'fixture');
        expect(before, isNotEmpty);

        await solo.unloadSource('fixture');
        // 端口关掉后，客户端拿不到任何结果（连接被拒 → 空列表）。
        final after = await probe.home('fixture', 'fixture');
        expect(after, isEmpty);
      } finally {
        await solo.stop();
      }
    });
  }, skip: ready ? false : '缺少 assets/runtime/node，先跑 tool/sync_runtime.sh');
}
