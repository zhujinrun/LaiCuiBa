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

  test('play resolves a single-url response', () async {
    await serve((request) async {
      expect(request.uri.path, '/spider/jianpian/3/play');
      bodyCache = await utf8.decodeStream(request);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'parse': 0,
          'url': 'https://cdn.example/ep1.m3u8',
        }),
      );
      await request.response.close();
    });

    final client = SpiderClient(port);
    final url = await client.play('nodejs_jianpian', '3', '575857', flag: 'LZ线路', nid: 1);

    expect(url, 'https://cdn.example/ep1.m3u8');
    expect(bodyCache, contains('"flag":"LZ线路"'));
    expect(bodyCache, contains('"nid":1'));
  });

  test('play resolves a list-form response', () async {
    await serve((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'list': [
            {'url': 'https://cdn.example/ep1.m3u8'},
          ],
        }),
      );
      await request.response.close();
    });

    final client = SpiderClient(port);
    final url = await client.play('nodejs_jianpian', '3', '575857');

    expect(url, 'https://cdn.example/ep1.m3u8');
  });

  test('play returns null when the source has nothing', () async {
    await serve((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({}));
      await request.response.close();
    });

    final client = SpiderClient(port);
    expect(await client.play('nodejs_jianpian', '3', '575857'), isNull);
  });

  test('parsePlayLines splits lines and episodes on the catvod separators', () {
    final lines = SpiderClient.parsePlayLines(
      r'LZ线路$$$盘夸克',
      r'第1集$https://a/1.m3u8#第2集$https://a/2.m3u8'
      r'$$$'
      r'正片$https://b/1.m3u8',
    );

    expect(lines, hasLength(2));
    expect(lines[0].name, 'LZ线路');
    expect(lines[0].episodes, hasLength(2));
    expect(lines[0].episodes[0].label, '第1集');
    expect(lines[0].episodes[0].url, 'https://a/1.m3u8');
    expect(lines[0].episodes[1].label, '第2集');
    expect(lines[0].episodes[1].url, 'https://a/2.m3u8');
    expect(lines[1].name, '盘夸克');
    expect(lines[1].episodes.single.label, '正片');
    expect(lines[1].episodes.single.url, 'https://b/1.m3u8');
  });

  test('parsePlayLines keeps a dollar sign inside the URL', () {
    final lines = SpiderClient.parsePlayLines(
      'LZ',
      r'第1集$https://a/sig=$x$y',
    );
    expect(lines.single.episodes.single.url, 'https://a/sig=\$x\$y');
  });

  test('parsePlayLines tolerates an empty from/url pair', () {
    expect(SpiderClient.parsePlayLines(null, null), isEmpty);
    expect(SpiderClient.parsePlayLines('', ''), isEmpty);
  });
}
