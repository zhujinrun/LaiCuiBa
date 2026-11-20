import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/spider_session.dart';

/// Exercises [SpiderSession] fan-out over a loopback spider server, using
/// `debugAttach` to skip the Node host and bundle download entirely.
void main() {
  HttpServer? server;
  late int port;
  final hitsPerSite = <String, int>{};

  Future<void> serve(
    FutureOr<void> Function(HttpRequest) handler,
  ) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server!.port;
    server!.listen(handler);
  }

  tearDown(() async {
    await server?.close(force: true);
    server = null;
  });

  SpiderSession session(int port) => SpiderSession(
    nodePath: 'node.exe',
    hostScript: 'cat_host.js',
    bundleRoot: Directory.systemTemp,
  )..debugAttach('douer', port);

  const jianpian = SiteInfo(key: 'nodejs_jianpian', name: '荐片', type: '3');
  const duoduo = SiteInfo(key: 'nodejs_duoduo', name: '盘多多', type: '3');

  test('search fans out over sites and tags results with siteKey', () async {
    hitsPerSite.clear();
    await serve((request) async {
      final path = request.uri.path;
      // Both sites answer, but duoduo returns nothing.
      final isJianpian = path == '/spider/jianpian/3/search';
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'list': isJianpian
              ? [
                  {
                    'vod_id': '575857',
                    'vod_name': '尚公主',
                    'vod_pic': 'https://img.example/1.webp',
                    'vod_remarks': '第40集',
                  },
                ]
              : [],
        }),
      );
      await request.response.close();
    });

    final s = session(port);
    final result = await s.search(
      sourceId: 'douer',
      md5Url: 'https://x/index.js.md5',
      sites: const [jianpian, duoduo],
      keyword: '尚公主',
    );

    expect(result.ok, isTrue);
    expect(result.total, 1);
    expect(result.groups, hasLength(1));
    expect(result.groups.first.site, '荐片');
    final item = result.groups.first.items.first;
    expect(item.siteKey, 'nodejs_jianpian');
    expect(item.title, '尚公主');
  });

  test('a site that throws is skipped without failing the whole search', () async {
    await serve((request) async {
      if (request.uri.path == '/spider/duoduo/3/search') {
        // Simulate a dead site by closing with an error status.
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'list': [
            {
              'vod_id': '1',
              'vod_name': '电影',
              'vod_pic': 'https://img.example/a.webp',
              'vod_remarks': 'HD',
            },
          ],
        }),
      );
      await request.response.close();
    });

    final s = session(port);
    final result = await s.search(
      sourceId: 'douer',
      md5Url: 'https://x/index.js.md5',
      sites: const [jianpian, duoduo],
      keyword: '电影',
    );

    expect(result.ok, isTrue);
    expect(result.total, 1);
    expect(result.groups.single.site, '荐片');
  });

  test('detail fetches the full record and re-tags the site', () async {
    await serve((request) async {
      expect(request.uri.path, '/spider/jianpian/3/detail');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'list': [
            {
              'vod_id': '575857',
              'vod_name': '尚公主',
              'vod_pic': 'https://img.example/1.webp',
              'type_name': '剧情/爱情',
              'vod_year': '2026',
              'vod_area': '中国大陆',
              'vod_actor': '孟子义/李昀锐',
              'vod_content': '简介',
            },
          ],
        }),
      );
      await request.response.close();
    });

    final s = session(port);
    final item = await s.detail(
      sourceId: 'douer',
      md5Url: 'https://x/index.js.md5',
      site: jianpian,
      vodId: '575857',
    );

    expect(item, isNotNull);
    expect(item!.title, '尚公主');
    expect(item.categories, ['剧情', '爱情']);
    expect(item.actors, ['孟子义', '李昀锐']);
    expect(item.siteKey, 'nodejs_jianpian');
  });

  test('home maps categories', () async {
    await serve((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'class': [
            {'type_id': '1', 'type_name': '电影'},
            {'type_id': '2', 'type_name': '电视剧'},
          ],
        }),
      );
      await request.response.close();
    });

    final s = session(port);
    final classes = await s.home(
      sourceId: 'douer',
      md5Url: 'https://x/index.js.md5',
      site: jianpian,
    );

    expect(classes, hasLength(2));
    expect(classes[0].name, '电影');
  });

  test('search reports failure when the session is not ready', () async {
    // A session that never attached: ensureLoaded would try to boot node, so we
    // drive the failure path through a broken bundle root instead.
    final s = SpiderSession(
      nodePath: 'node.exe',
      hostScript: 'cat_host.js',
      bundleRoot: Directory.systemTemp,
    );
    // Point ensureLoaded at a directory that cannot be created.
    final result = await s.search(
      sourceId: 'douer',
      md5Url: 'file:///definitely/missing/index.js.md5',
      sites: const [jianpian],
      keyword: 'x',
    );
    expect(result.ok, isFalse);
  });

  test('searchStream emits sites in completion order, not declaration order',
      () async {
    await serve((request) async {
      // duoduo answers fast, jianpian answers slowly -- even though jianpian is
      // declared first, its hits must not appear before duoduo's.
      final isJianpian = request.uri.path == '/spider/jianpian/3/search';
      if (isJianpian) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'list': [
            {
              'vod_id': isJianpian ? '575857' : '9985',
              'vod_name': isJianpian ? '尚公主' : '别的剧',
              'vod_pic': 'https://img.example/1.webp',
              'vod_remarks': '第1集',
            },
          ],
        }),
      );
      await request.response.close();
    });

    final s = session(port);
    final seen = <String>[];
    await for (final group in s.searchStream(
      sourceId: 'douer',
      md5Url: 'https://x/index.js.md5',
      sites: const [jianpian, duoduo],
      keyword: '剧',
    )) {
      seen.add(group.site);
    }

    expect(seen, ['盘多多', '荐片']);
  });
}
