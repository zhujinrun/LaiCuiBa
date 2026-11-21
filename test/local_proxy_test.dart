import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/local_proxy.dart';
import 'package:lai_cui_ba/services/py_host.dart';

import 'support/fake_py_host.dart';

/// The two endpoints a Python source reaches through `getProxyUrl()` and
/// `getCache()`. Tested over a real loopback listener because the contract *is*
/// HTTP: a fake server would only prove the fake agrees with itself.
void main() {
  late LocalProxyServer server;
  late FakePyHost host;

  setUp(() async {
    host = FakePyHost(
      bodies: const {},
      proxyAnswer: PyProxyResponse(
        status: 200,
        mime: 'video/vnd.mpegurl',
        body: utf8.encode('#EXTM3U\n#EXT-X-VERSION:3\n'),
        headers: const {'x-source': 'fixture'},
      ),
    );
    server = LocalProxyServer(hostProvider: () => host);
    await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  Future<HttpClientResponse> get(String path) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}$path'),
      );
      return await request.close();
    } finally {
      client.close();
    }
  }

  Future<HttpClientResponse> post(String path, String body) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}$path'),
      );
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      request.write(body);
      return await request.close();
    } finally {
      client.close();
    }
  }

  test('binds an ephemeral loopback port', () async {
    expect(server.port, greaterThan(0));
    expect(server.isRunning, isTrue);
  });

  test('/proxy answers with the source\'s status, type and bytes', () async {
    final response = await get(
      '/proxy?do=py&url=http%3A%2F%2Fa.invalid%2F1.m3u8',
    );
    expect(response.statusCode, 200);
    expect(response.headers.contentType?.mimeType, 'video/vnd.mpegurl');
    expect(response.headers.value('x-source'), 'fixture');
    // Proxied answers must never be cached: the same URL can hand back a new
    // token on the next request.
    expect(response.headers.value('cache-control'), 'no-store');
    expect(await utf8.decodeStream(response), contains('#EXTM3U'));
  });

  test('/cache stores, returns and deletes a value', () async {
    final set = await post('/cache?do=set&key=token', 'value=abc%2B123');
    expect(set.statusCode, 200);
    await set.drain<void>();

    final got = await get('/cache?do=get&key=token');
    expect(got.statusCode, 200);
    expect(await utf8.decodeStream(got), 'abc+123');

    final del = await get('/cache?do=del&key=token');
    expect(del.statusCode, 200);
    await del.drain<void>();

    final gone = await get('/cache?do=get&key=token');
    expect(await utf8.decodeStream(gone), isEmpty);
  });

  test(
    'the cache keeps values a source asks for by a different key apart',
    () async {
      await (await post('/cache?do=set&key=a', 'value=1')).drain<void>();
      await (await post('/cache?do=set&key=b', 'value=2')).drain<void>();
      expect(server.debugCache, {'a': '1', 'b': '2'});
    },
  );

  test('a proxy failure is reported as 502, not as an empty body', () async {
    final failing = LocalProxyServer(
      hostProvider: () => throw const PyHostException('没有可用的源实例'),
    );
    await failing.start();
    addTearDown(failing.stop);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${failing.port}/proxy?do=py'),
    );
    final response = await request.close();
    expect(response.statusCode, 502);
    expect(await utf8.decodeStream(response), contains('没有可用的源实例'));
  });

  test('an unknown path is a 404 rather than a proxy attempt', () async {
    final response = await get('/nope');
    expect(response.statusCode, 404);
    await response.drain<void>();
  });
}
