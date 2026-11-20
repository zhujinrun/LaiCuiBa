import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/config_fetcher.dart';

/// A throwaway HTTP server on loopback, so the fetcher is exercised against the
/// real socket path (status codes, timeouts, size limits) without the internet.
void main() {
  HttpServer? server;
  late String base;

  Future<void> serve(FutureOr<void> Function(HttpRequest) handler) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server!.port}';
    server!.listen((request) {
      handler(request);
    });
  }

  tearDown(() async {
    await server?.close(force: true);
    server = null;
  });

  void respond(HttpRequest request, String body, {int status = 200}) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(body);
    request.response.close();
  }

  test('a JSON config over HTTP becomes sites', () async {
    await serve((request) async {
      respond(
        request,
        jsonEncode({
          'sites': [
            {'key': 'a', 'name': 'A 站', 'type': 3, 'api': 'https://a/api.php'},
            {'key': 'b', 'name': 'B 站', 'type': 1, 'api': 'https://b/api.php'},
          ],
        }),
      );
    });

    final result = await fetchConfig('$base/config.json');

    expect(result.ok, isTrue);
    expect(result.sites.map((site) => site.name), ['A 站', 'B 站']);
    // The request really happened, so a latency was measured.
    expect(result.latencyMs, greaterThanOrEqualTo(0));
    expect(result.note, isNull);
  });

  test('a per-line 名称\$地址 document is parsed too', () async {
    await serve((request) async {
      respond(request, '甲站\$https://jia/api.php\n乙站\$https://yi/api.php');
    });

    final result = await fetchConfig('$base/sites.txt');

    expect(result.ok, isTrue);
    expect(result.sites, hasLength(2));
  });

  test('a silenced site is reported in the note', () async {
    await serve((request) async {
      respond(
        request,
        jsonEncode({
          'sites': [
            {'key': 'a', 'name': 'A', 'type': 3, 'searchable': 0},
            {'key': 'b', 'name': 'B', 'type': 3},
          ],
        }),
      );
    });

    final result = await fetchConfig('$base/config.json');

    expect(result.ok, isTrue);
    expect(result.note, contains('1 个默认不参与搜索'));
    expect(result.sites.where((site) => site.enabled), hasLength(1));
  });

  test('a non-200 status is reported with its code', () async {
    await serve((request) async {
      respond(request, 'nope', status: 404);
    });

    final result = await fetchConfig('$base/missing.json');

    expect(result.ok, isFalse);
    expect(result.error, contains('404'));
    expect(result.sites, isEmpty);
  });

  test('a js bundle is explained instead of being called a failure', () async {
    await serve((request) async {
      respond(
        request,
        'var spider = (function(){ '
        'meta:{key:"duoduo",name:"「盘」多多",type:3}; '
        'module.exports = {init: function(){}}; })();',
      );
    });

    final result = await fetchConfig('$base/index.js');

    expect(result.sites, isEmpty);
    // Not an error: the source is fine, this build just cannot enumerate it.
    expect(result.error, isNull);
    expect(result.note, contains('js 源'));
  });

  test('an .md5 address retries without the suffix', () async {
    await serve((request) async {
      final path = request.uri.path;
      if (path.endsWith('.md5')) {
        respond(request, 'd41d8cd98f00b204e9800998ecf8427e');
        return;
      }
      respond(
        request,
        jsonEncode({
          'sites': [
            {'key': 'z', 'name': 'Z 站', 'type': 3},
          ],
        }),
      );
    });

    final result = await fetchConfig('$base/index.config.json.md5');

    expect(result.ok, isTrue);
    expect(result.sites.single.name, 'Z 站');
  });

  test('a slow server hits the timeout', () async {
    await serve((request) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      respond(request, '{}');
    });

    final result = await fetchConfig(
      '$base/slow.json',
      timeout: const Duration(milliseconds: 250),
    );

    expect(result.ok, isFalse);
    expect(result.error, contains('超时'));
  });

  test('a huge response is refused instead of buffered', () async {
    await serve((request) async {
      // 9 MB of padding: not a config document by any measure.
      request.response.statusCode = 200;
      request.response.write('{"sites":[');
      final chunk = 'x' * (1024 * 1024);
      for (var i = 0; i < 9; i++) {
        request.response.write(chunk);
      }
      await request.response.close();
    });

    final result = await fetchConfig('$base/huge.json');

    expect(result.ok, isFalse);
    expect(result.error, contains('MB'));
  });

  test('bad addresses are rejected without a request', () async {
    expect((await fetchConfig('')).error, contains('为空'));
    expect((await fetchConfig('not a url')).error, isNotNull);
    expect((await fetchConfig('ftp://example.com/x')).error, contains('http'));
  });

  test('a connection to a closed port reports instead of throwing', () async {
    // Bind then close, so the port is almost certainly free.
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close(force: true);

    final result = await fetchConfig('http://127.0.0.1:$port/config.json');

    expect(result.ok, isFalse);
    expect(result.error, isNotNull);
  });
}
