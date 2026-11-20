import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/spider_client.dart';

/// Exercises the spider client against a loopback server that mimics the
/// catvod `POST /spider/:key/:type/:action` routes, so the vod mapping and the
/// `nodejs_` prefix strip are checked without the Node runtime.
void main() {
  test('spiderKey strips the nodejs_ prefix and keeps the bare key', () {
    expect(SpiderClient.spiderKey('nodejs_jianpian'), 'jianpian');
    expect(SpiderClient.spiderKey('duoduo'), 'duoduo');
    expect(SpiderClient.spiderKey(''), '');
  });

  HttpServer? server;
  late int port;

  // Captured request body, set inside each handler for later assertion.
  String? bodyCache;

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

  test('search maps vod rows onto MediaItem and strips the prefix', () async {
    await serve((request) async {
      // The client strips nodejs_ before building the URL.
      expect(request.uri.path, '/spider/jianpian/3/search');
      bodyCache = await utf8.decodeStream(request);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'page': 1,
          'pagecount': 2,
          'total': 9762,
          'list': [
            {
              'vod_id': '575857',
              'vod_name': '尚公主',
              'vod_pic': 'https://img.example/1.webp',
              'vod_remarks': '第40集',
            },
          ],
        }),
      );
      await request.response.close();
    });

    final client = SpiderClient(port);
    final result = await client.search('nodejs_jianpian', '3', '尚公主');

    expect(result.total, 9762);
    expect(result.items, hasLength(1));
    final item = result.items.first;
    expect(item.id, '575857');
    expect(item.title, '尚公主');
    expect(item.image, 'https://img.example/1.webp');
    expect(item.tag, '第40集');
    expect(item.latest, '第40集');
    // The request body carried the keyword.
    expect(bodyCache, contains('尚公主'));
  });

  test('detail uses the singular id and fills full fields', () async {
    await serve((request) async {
      expect(request.uri.path, '/spider/jianpian/3/detail');
      bodyCache = await utf8.decodeStream(request);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'list': [
            {
              'vod_id': '575857',
              'vod_name': '尚公主',
              'vod_pic': 'https://img.example/1.webp',
              'type_name': '剧情/爱情/古装',
              'vod_year': '2026',
              'vod_area': '中国大陆',
              'vod_remarks': '第40集',
              'vod_actor': '孟子义/李昀锐',
              'vod_director': '秦榛',
              'vod_content': '不甘命运的天家嫡女',
            },
          ],
        }),
      );
      await request.response.close();
    });

    final client = SpiderClient(port);
    final item = await client.detail('nodejs_jianpian', '3', '575857');

    expect(item, isNotNull);
    expect(item!.year, 2026);
    expect(item.area, '中国大陆');
    expect(item.categories, ['剧情', '爱情', '古装']);
    expect(item.actors, ['孟子义', '李昀锐']);
    expect(item.overview, '不甘命运的天家嫡女');
    expect(item.siteKey, 'nodejs_jianpian');
    expect(bodyCache, contains('"id":"575857"'));
  });

  test('home maps the class list to SpiderClass rows', () async {
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

    final client = SpiderClient(port);
    final classes = await client.home('nodejs_jianpian', '3');

    expect(classes, hasLength(2));
    expect(classes[0].typeId, '1');
    expect(classes[0].name, '电影');
  });

  test('an empty category list is not an error', () async {
    await serve((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'page': 1, 'pagecount': 1, 'limit': 20, 'total': 0, 'list': []}),
      );
      await request.response.close();
    });

    final client = SpiderClient(port);
    final result = await client.category('nodejs_jianpian', '3', tid: '1');

    expect(result.items, isEmpty);
    expect(result.total, 0);
  });
}
