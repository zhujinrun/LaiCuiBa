import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:lai_cui_ba/services/js_host.dart';
import 'package:lai_cui_ba/services/source_host.dart';

/// The real thing: `node.exe` running `js_site_host.js`, talking the same
/// line-JSON protocol as the Python host, against a real (local) web site.
///
/// The fixture source (`test/fixtures/js_source/main.js`) is written the way a
/// TVBox `.js` site is written — synchronous `req`, `pdfh`/`pdfa` over real
/// HTML — so a green run here means the bridge actually works, not that it can
/// replay canned JSON.
void main() {
  final host = File(p.join('assets', 'runtime', 'node', 'js_site_host.js'));
  final node = File(p.join('assets', 'runtime', 'node', 'node.exe'));
  final fixture = File(p.join('test', 'fixtures', 'js_source', 'main.js'));
  final ready = node.existsSync() && host.existsSync() && fixture.existsSync();

  late HttpServer server;
  late String base;
  late Directory dataDir;
  var hits = 0;

  setUpAll(() async {
    if (!ready) return;
    // A three-page site: the fixture parses these with pdfh/pdfa, so the HTML
    // shape matters (a real source would face the same thing).
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    dataDir = await Directory.systemTemp.createTemp('lcb_jssrc_');
    server.listen((request) async {
      hits++;
      request.response.headers.contentType = ContentType.html;
      switch (request.uri.path) {
        case '/home':
          request.response.write(
            '<html><body><ul class="nav">'
            '<li><a data-id="1" href="/list?tid=1">电影</a></li>'
            '<li><a data-id="2" href="/list?tid=2">剧集</a></li>'
            '</ul></body></html>',
          );
        case '/list':
          request.response.write(
            '<html><body>'
            '<div class="item"><a data-id="101" href="/detail?id=101">三体</a>'
            '<img data-original="http://img.invalid/1.jpg">'
            '<span class="remark">全30集</span></div>'
            '<div class="item"><a data-id="102" href="/detail?id=102">狂飙</a>'
            '<img data-original="http://img.invalid/2.jpg">'
            '<span class="remark">更新至12集</span></div>'
            '</body></html>',
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
  });

  tearDownAll(() async {
    if (!ready) return;
    await server.close(force: true);
    if (dataDir.existsSync()) await dataDir.delete(recursive: true);
  });

  test('宿主回答 ping，说出自己的版本', () async {
    final h = JsHost(
      nodePath: node.path,
      hostScript: host.path,
      dataDir: dataDir.path,
    );
    addTearDown(h.stop);
    await h.start();
    expect(await h.ping(), contains('v18'));
  }, skip: ready ? false : '缺少 node 运行时（先跑 tool/sync_runtime.sh）');

  test('home / category / search / detail / player 都走真的 req + pdfh', () async {
    final h = JsHost(
      nodePath: node.path,
      hostScript: host.path,
      dataDir: dataDir.path,
    );
    addTearDown(h.stop);
    await h.start();

    final home = jsonDecode(
      await h.call(
        key: 'js|a',
        path: fixture.path,
        method: 'home',
        ext: base,
        args: [true],
      ),
    ) as Map<String, dynamic>;
    final classes = home['class'] as List;
    expect(classes, hasLength(2));
    expect(classes.first['type_id'], '1');
    expect(classes.first['type_name'], '电影');

    final list = jsonDecode(
      await h.call(
        key: 'js|a',
        path: fixture.path,
        method: 'category',
        ext: base,
        args: ['1', '1', true, {}],
      ),
    ) as Map<String, dynamic>;
    final items = list['list'] as List;
    expect(items, hasLength(2));
    expect(items.first['vod_name'], '三体');
    expect(items.first['vod_pic'], 'http://img.invalid/1.jpg');
    expect(items.first['vod_remarks'], '全30集');

    final search = jsonDecode(
      await h.call(
        key: 'js|a',
        path: fixture.path,
        method: 'search',
        ext: base,
        args: ['三体', false, '1'],
      ),
    ) as Map<String, dynamic>;
    expect((search['list'] as List).first['vod_id'], '101');

    final detail = jsonDecode(
      await h.call(
        key: 'js|a',
        path: fixture.path,
        method: 'detail',
        ext: base,
        args: ['101'],
      ),
    ) as Map<String, dynamic>;
    final record = (detail['list'] as List).first as Map<String, dynamic>;
    expect(record['vod_name'], '三体');
    expect(record['vod_pic'], 'http://img.invalid/p.jpg');
    expect(record['vod_content'], '科幻小说改编');
    expect(record['vod_play_from'], '线路一\$\$\$线路二');
    expect(record['vod_play_url'], contains('第1集\$http://cdn.invalid/1.m3u8'));

    final play = jsonDecode(
      await h.call(
        key: 'js|a',
        path: fixture.path,
        method: 'player',
        ext: base,
        args: ['线路一', 'http://cdn.invalid/1.m3u8', []],
      ),
    ) as Map<String, dynamic>;
    expect(play['parse'], 0);
    expect(play['url'], '$base/media/http://cdn.invalid/1.m3u8.m3u8');
    expect((play['header'] as Map)['Referer'], '$base/');

    // One source, five entries, and the site was really hit for each of them.
    expect(hits, greaterThanOrEqualTo(4));
  }, skip: ready ? false : '缺少 node 运行时（先跑 tool/sync_runtime.sh）');

  test('源抛出的异常原样回到 Dart，不当成空结果', () async {
    final h = JsHost(
      nodePath: node.path,
      hostScript: host.path,
      dataDir: dataDir.path,
    );
    addTearDown(h.stop);
    await h.start();
    await expectLater(
      h.call(
        key: 'js|a',
        path: fixture.path,
        method: 'search',
        ext: base,
        args: ['boom', false, '1'],
      ),
      throwsA(
        isA<SourceHostException>().having(
          (e) => e.message,
          'message',
          contains('夹具故意炸'),
        ),
      ),
    );
  }, skip: ready ? false : '缺少 node 运行时（先跑 tool/sync_runtime.sh）');

  test('没有实现的方法如实报出来，而不是回空列表', () async {
    final h = JsHost(
      nodePath: node.path,
      hostScript: host.path,
      dataDir: dataDir.path,
    );
    addTearDown(h.stop);
    await h.start();
    await expectLater(
      h.call(
        key: 'js|a',
        path: fixture.path,
        method: 'live',
        ext: base,
        args: [''],
      ),
      throwsA(
        isA<SourceHostException>().having(
          (e) => e.message,
          'message',
          contains('liveContent'),
        ),
      ),
    );
  }, skip: ready ? false : '缺少 node 运行时（先跑 tool/sync_runtime.sh）');

  test('localProxy 的字节原样回到 Dart', () async {
    final h = JsHost(
      nodePath: node.path,
      hostScript: host.path,
      dataDir: dataDir.path,
    );
    addTearDown(h.stop);
    await h.start();
    await h.call(
      key: 'js|a',
      path: fixture.path,
      method: 'home',
      ext: base,
      args: [true],
    );
    final answer = await h.proxy({'url': 'http://a.invalid/b', 'do': 'js'});
    expect(answer.status, 200);
    expect(answer.mime, 'text/plain');
    expect(utf8.decode(answer.body), 'proxied:http://a.invalid/b');
  }, skip: ready ? false : '缺少 node 运行时（先跑 tool/sync_runtime.sh）');

  test('release 之后再调用会重新 init 一次', () async {
    final h = JsHost(
      nodePath: node.path,
      hostScript: host.path,
      dataDir: dataDir.path,
    );
    addTearDown(h.stop);
    await h.start();
    final first = await h.call(
      key: 'js|b',
      path: fixture.path,
      method: 'home',
      ext: base,
      args: [true],
    );
    expect(first, contains('电影'));
    await h.release('js|b');
    final again = await h.call(
      key: 'js|b',
      path: fixture.path,
      method: 'home',
      ext: base,
      args: [true],
    );
    expect(again, contains('电影'));
  }, skip: ready ? false : '缺少 node 运行时（先跑 tool/sync_runtime.sh）');

  test('源文件不存在时说的是人话', () async {
    final h = JsHost(
      nodePath: node.path,
      hostScript: host.path,
      dataDir: dataDir.path,
    );
    addTearDown(h.stop);
    await h.start();
    await expectLater(
      h.call(
        key: 'js|missing',
        path: p.join(dataDir.path, 'nope.js'),
        method: 'home',
        ext: base,
        args: [true],
      ),
      throwsA(
        isA<SourceHostException>().having(
          (e) => e.message,
          'message',
          contains('源文件不存在'),
        ),
      ),
    );
  }, skip: ready ? false : '缺少 node 运行时（先跑 tool/sync_runtime.sh）');
}
