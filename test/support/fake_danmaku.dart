import 'dart:convert';
import 'dart:io';

import 'package:lai_cui_ba/services/danmaku/danmaku_api.dart';

/// A dandanplay-shaped server that answers the three endpoints we use.
///
/// The real client is judged on the contract: which path it calls, what it puts
/// in `X-AppId` / `X-Timestamp` / `X-Signature`, and what it makes of XML vs
/// JSON bodies. None of that needs the public internet, so these tests run
/// offline and still cover the signature and the 401 path.
class FakeDanmaku {
  FakeDanmaku._(this._server, this.mode, this.appId, this.appSecret);

  final HttpServer _server;

  /// `open` answers anyone; `signed` rejects requests without a valid signature.
  final String mode;
  final String appId;
  final String appSecret;

  /// Every request seen, as `METHOD /path?query`.
  final List<String> requests = [];

  /// The last `X-*` headers, for signature assertions.
  Map<String, String> lastAuth = {};

  /// Switch the comment body format: `json` (default) or `xml`.
  String commentFormat = 'json';

  /// When false both endpoints answer "nothing found" — a source that is up but
  /// simply does not carry this show.
  bool matched = true;

  /// When true, `/comment` returns an empty list instead of 3 danmaku.
  bool emptyComments = false;

  /// When true, `/comment` answers with an HTML page — the shape a captive
  /// portal or a login wall produces.
  bool garbageComments = false;

  static const String anime = '三体';
  static const int episodeId = 1043721;

  static Future<FakeDanmaku> start({
    String mode = 'open',
    String appId = 'app-1',
    String appSecret = 'secret-1',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeDanmaku._(server, mode, appId, appSecret);
    server.listen(fake._handle);
    return fake;
  }

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  /// A source pointed at this server.
  DanmakuSource source({
    String id = 'fake',
    String name = '测试源',
    bool withCredentials = false,
  }) =>
      DanmakuSource(
        id: id,
        name: name,
        baseUrl: baseUrl,
        appId: withCredentials ? appId : '',
        appSecret: withCredentials ? appSecret : '',
      );

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    requests.add('${request.method} $path?${request.uri.query}');
    lastAuth = {
      for (final name in ['x-appid', 'x-timestamp', 'x-signature'])
        if (request.headers.value(name) != null)
          name: request.headers.value(name)!,
    };

    if (mode == 'signed' && !_signatureOk(request, path)) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }

    request.response.headers.contentType = ContentType.json;
    if (path == '/api/v2/search/episodes') {
      final episode = request.uri.queryParameters['episode'] ?? '';
      final animeName = request.uri.queryParameters['anime'] ?? '';
      final hit = matched && animeName.contains('三体') && episode == '3';
      request.response.write(jsonEncode({
        'errorCode': 0,
        'animes': hit
            ? [
                {
                  'animeTitle': anime,
                  'episodes': [
                    {
                      'episodeId': episodeId,
                      'episodeTitle': '第3话',
                    },
                  ],
                },
              ]
            : [],
      }));
      await request.response.close();
      return;
    }

    if (path == '/api/v2/match') {
      final body = await utf8.decoder.bind(request).join();
      final fileName = body.isEmpty
          ? ''
          : '${(jsonDecode(body) as Map)['fileName'] ?? ''}';
      request.response.write(jsonEncode({
        'errorCode': 0,
        'isMatched': matched && fileName.contains(anime),
        'matches': matched && fileName.contains(anime)
            ? [
                {
                  'episodeId': episodeId,
                  'animeTitle': anime,
                  'episodeTitle': '第3话',
                },
              ]
            : [],
      }));
      await request.response.close();
      return;
    }

    if (path.startsWith('/api/v2/comment/')) {
      if (garbageComments) {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html><body>需要登录</body></html>');
        await request.response.close();
        return;
      }
      if (emptyComments) {
        request.response.write(jsonEncode({'errorCode': 0, 'comments': []}));
        await request.response.close();
        return;
      }
      if (commentFormat == 'xml') {
        // `write` would encode with the response's charset (latin1 for
        // text/xml), so the Chinese text has to go out as UTF-8 bytes.
        request.response.headers.contentType =
            ContentType('text', 'xml', charset: 'utf-8');
        request.response.add(utf8.encode(
          '<?xml version="1.0" encoding="UTF-8"?><i>'
          '<d p="1.5,1,16777215,abc">第一条 &amp; 转义</d>'
          '<d p="3.0,5,255,def">顶部</d>'
          '<d p="9.25,4,65280,ghi">底部</d>'
          '</i>',
        ));
        await request.response.close();
        return;
      }
      request.response.write(jsonEncode({
        'errorCode': 0,
        'comments': [
          {'cid': 1, 'p': '1.5,1,16777215,abc', 'm': '第一条'},
          {'cid': 2, 'p': '3.0,5,16711680,def', 'm': '顶部'},
          {'cid': 3, 'p': '9.25,4,65280,ghi', 'm': '底部'},
        ],
      }));
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  /// Recomputes the signature the way the official docs describe it: the path
  /// *without* the query string, plus the timestamp the client sent.
  bool _signatureOk(HttpRequest request, String path) {
    final appId = request.headers.value('x-appid');
    final timestamp = request.headers.value('x-timestamp');
    final signature = request.headers.value('x-signature');
    if (appId == null || timestamp == null || signature == null) return false;
    if (appId != this.appId) return false;
    final expected = danmakuSignature(
      appId: this.appId,
      appSecret: appSecret,
      timestamp: int.tryParse(timestamp) ?? 0,
      path: path,
    );
    return signature == expected;
  }
}
