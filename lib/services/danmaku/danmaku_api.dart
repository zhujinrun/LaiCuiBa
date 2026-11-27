import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// 一条弹幕。
///
/// 字段沿用 dandanplay 的 `p` 属性：`时间秒,模式,颜色,用户哈希`。模式 `1` 从右往左
/// 滚、`4` 钉在底部、`5` 钉在顶部；颜色是 `0xRRGGBB` 的十进制整数。
///
/// 解析层不认识的模式一律当滚动（`1`）——它们大多是高级弹幕/代码弹幕，按普通文字
/// 画出来至少不会丢内容，也不会画错位置。
class DanmakuComment {
  const DanmakuComment({
    required this.timeMs,
    required this.text,
    this.mode = scroll,
    this.color = 0xFFFFFF,
  });

  static const int scroll = 1;
  static const int bottom = 4;
  static const int top = 5;

  final int timeMs;
  final String text;
  final int mode;
  final int color;

  bool get isScroll => mode != top && mode != bottom;

  @override
  String toString() => 'DanmakuComment($timeMs, $mode, $text)';
}

/// 弹幕源说不了话时抛这个：消息直接给用户看，所以每条都写清"用户能做什么"。
class DanmakuException implements Exception {
  const DanmakuException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 匹配到的一集。
class DanmakuMatch {
  const DanmakuMatch({
    required this.episodeId,
    required this.animeTitle,
    required this.episodeTitle,
  });

  final int episodeId;
  final String animeTitle;
  final String episodeTitle;

  String get label =>
      episodeTitle.isEmpty ? animeTitle : '$animeTitle · $episodeTitle';
}

/// 一个弹幕源。契约是 dandanplay 的 `/api/v2/*`。
///
/// 没有 `appId`/`appSecret` 就不发签名头：自建的同构服务器一般不要签名，官方
/// `api.dandanplay.net` 会回 401，那时 [DanmakuApi] 会把话说清楚，让用户去填。
class DanmakuSource {
  const DanmakuSource({
    required this.id,
    required this.name,
    this.baseUrl = officialBase,
    this.appId = '',
    this.appSecret = '',
    this.enabled = true,
  });

  static const String officialBase = 'https://api.dandanplay.net';

  /// 内置源，永远排在用户源之前：地址固定，改不了，删不掉。
  static const DanmakuSource builtin = DanmakuSource(
    id: 'dandanplay',
    name: '弹弹play',
  );

  final String id;
  final String name;
  final String baseUrl;
  final String appId;
  final String appSecret;
  final bool enabled;

  bool get hasCredentials => appId.isNotEmpty && appSecret.isNotEmpty;

  bool get isBuiltin => id == builtin.id;

  /// 官方接口必须签名；自建的 dandanplay 兼容服务不需要 AppId/AppSecret。
  bool get needsCredentials => baseUrl.trim().isEmpty
      ? isBuiltin
      : Uri.tryParse(baseUrl)?.host.toLowerCase() ==
          Uri.parse(officialBase).host.toLowerCase();

  DanmakuSource copyWith({
    String? name,
    String? baseUrl,
    String? appId,
    String? appSecret,
    bool? enabled,
  }) =>
      DanmakuSource(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        appId: appId ?? this.appId,
        appSecret: appSecret ?? this.appSecret,
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'appId': appId,
        'appSecret': appSecret,
        'enabled': enabled,
      };

  /// 坏掉的一条只丢掉自己，不能让整张源表加载失败。
  static DanmakuSource? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}'.trim();
    final name = '${raw['name'] ?? ''}'.trim();
    if (id.isEmpty || name.isEmpty) return null;
    final base = '${raw['baseUrl'] ?? ''}'.trim();
    return DanmakuSource(
      id: id,
      name: name,
      baseUrl: base.isEmpty ? officialBase : stripTrailingSlash(base),
      appId: '${raw['appId'] ?? ''}'.trim(),
      appSecret: '${raw['appSecret'] ?? ''}'.trim(),
      enabled: raw['enabled'] != false,
    );
  }

  static String stripTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

/// 所有启用的源都是「必须签名却没填凭据」时，点弹幕只能去要 401。
/// 这时候不要发请求，也不要在进播放页时挂提示——等用户主动点开再说。
bool danmakuSourcesNeedCredentials(Iterable<DanmakuSource> sources) {
  final enabled = sources.where((source) => source.enabled).toList();
  if (enabled.isEmpty) return true;
  return enabled.every(
    (source) => source.needsCredentials && !source.hasCredentials,
  );
}

/// dandanplay 的签名：`base64(sha256(appId + timestamp + path + appSecret))`。
///
/// `path` 是带前导斜杠的接口路径（`/api/v2/match`），不含域名和查询串。
String danmakuSignature({
  required String appId,
  required String appSecret,
  required int timestamp,
  required String path,
}) {
  final raw = '$appId$timestamp$path$appSecret';
  return base64Encode(sha256.convert(utf8.encode(raw)).bytes);
}

/// dandanplay 兼容接口的客户端。
///
/// 只实现我们真正需要的三个接口：按文件名匹配、按片名+集数搜索、取某集弹幕。
/// 每个请求都可以注入 [HttpClient]，测试用真 `HttpServer` 验签名与解析，不打外网。
class DanmakuApi {
  DanmakuApi(
    this.source, {
    HttpClient? http,
    this.timeout = const Duration(seconds: 10),
  })  : _http = http ?? HttpClient(),
        _ownsHttp = http == null {
    _base = DanmakuSource.stripTrailingSlash(source.baseUrl);
  }

  final DanmakuSource source;
  final Duration timeout;
  final HttpClient _http;
  final bool _ownsHttp;
  late final String _base;

  /// `GET /api/v2/search/episodes?anime=&episode=` — 没有文件也能匹配，只要
  /// 知道片名和集数。播放页拿到的正是这两样，所以这是首选路径。
  Future<List<DanmakuMatch>> searchEpisodes(
    String anime,
    String episode,
  ) async {
    final result = await _send(
      'GET',
      '/api/v2/search/episodes',
      query: {'anime': anime, 'episode': episode},
    );
    final json = result.json;
    if (json is! Map) throw DanmakuException(_badBody(result));
    final list = json['animes'];
    final out = <DanmakuMatch>[];
    if (list is List) {
      for (final anime in list) {
        if (anime is! Map) continue;
        final title = '${anime['animeTitle'] ?? ''}';
        final eps = anime['episodes'];
        if (eps is! List) continue;
        for (final ep in eps) {
          if (ep is! Map) continue;
          final id = _intOf(ep['episodeId']);
          if (id == null) continue;
          out.add(DanmakuMatch(
            episodeId: id,
            animeTitle: title,
            episodeTitle: '${ep['episodeTitle'] ?? ''}',
          ));
        }
      }
    }
    return out;
  }

  /// `POST /api/v2/match` — 传文件名（和可选的哈希/时长），服务器自己猜是哪一集。
  Future<List<DanmakuMatch>> matchFile({
    required String fileName,
    int? fileSize,
    int? durationMs,
    String? fileHash,
  }) async {
    final result = await _send(
      'POST',
      '/api/v2/match',
      body: {
        'fileName': fileName,
        if (fileHash != null && fileHash.isNotEmpty) 'fileHash': fileHash,
        if (fileSize != null) 'fileSize': fileSize,
        if (durationMs != null) 'videoDuration': durationMs ~/ 1000,
        'matchMode': fileHash != null && fileHash.isNotEmpty
            ? 'hashAndFileName'
            : 'fileNameOnly',
      },
    );
    final json = result.json;
    if (json is! Map) throw DanmakuException(_badBody(result));
    final matches = json['matches'];
    final out = <DanmakuMatch>[];
    if (matches is List) {
      for (final m in matches) {
        if (m is! Map) continue;
        final id = _intOf(m['episodeId']);
        if (id == null) continue;
        out.add(DanmakuMatch(
          episodeId: id,
          animeTitle: '${m['animeTitle'] ?? ''}',
          episodeTitle: '${m['episodeTitle'] ?? ''}',
        ));
      }
    }
    return out;
  }

  /// `GET /api/v2/comment/{episodeId}` — 该集的弹幕，按时间排好。
  Future<List<DanmakuComment>> comments(
    int episodeId, {
    bool withRelated = false,
  }) async {
    final result = await _send(
      'GET',
      '/api/v2/comment/$episodeId',
      query: {'withRelated': withRelated ? 'true' : 'false', 'chConvert': '0'},
    );
    final list = parseDanmaku(result.text);
    if (list.isEmpty && result.json == null) {
      throw DanmakuException(_badBody(result));
    }
    list.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return list;
  }

  void close() {
    if (_ownsHttp) _http.close(force: true);
  }

  Future<_Reply> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var uri = Uri.parse('$_base$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final request = await _http.openUrl(method, uri).timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json, */*');
    if (body != null) {
      request.headers.contentType = ContentType.json;
    }
    // 只有填了凭据才签名：自建源通常不校验，硬塞一个空签名反而会被拒。
    if (source.hasCredentials) {
      request.headers.set('X-AppId', source.appId);
      request.headers.set('X-Timestamp', '$ts');
      request.headers.set(
        'X-Signature',
        danmakuSignature(
          appId: source.appId,
          appSecret: source.appSecret,
          timestamp: ts,
          path: path,
        ),
      );
    }
    if (body != null) request.write(jsonEncode(body));

    final response = await request.close().timeout(timeout);
    final text = await utf8.decoder.bind(response).join().timeout(timeout);
    final status = response.statusCode;
    if (status == 401 || status == 403) {
      throw DanmakuException(
        source.isBuiltin
            ? '弹弹play 要求 AppId/AppSecret：到 dandanplay 开发者后台申请，'
                '填进这个弹幕源；或者换一个自建的同构服务器。'
            : '「${source.name}」拒绝了请求（$status）：检查 AppId/AppSecret，'
                '或这个地址是不是 dandanplay 兼容接口。',
      );
    }
    if (status == 404) throw DanmakuException('「${source.name}」没有这个接口（404）');
    if (status < 200 || status >= 300) {
      throw DanmakuException('「${source.name}」返回 $status');
    }
    Object? json;
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        json = jsonDecode(text);
      } on FormatException {
        json = null;
      }
    }
    return _Reply(text: text, json: json);
  }

  String _badBody(_Reply r) {
    final head = r.text.trim();
    final preview = head.length > 60 ? '${head.substring(0, 60)}…' : head;
    return '「${source.name}」返回的不是弹幕接口格式：${preview.isEmpty ? '空响应' : preview}';
  }

  static int? _intOf(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw');
  }
}

class _Reply {
  const _Reply({required this.text, required this.json});

  final String text;
  final Object? json;
}

/// 把服务器返回的弹幕解析成 [DanmakuComment]。
///
/// dandanplay 的 `/comment` 在 `Accept: application/xml` 时返回 XML、其它情况
/// 可能返回 JSON；自建服务器两种都见过，所以两种都认。认不出就返回空表，让上层
/// 报"不是弹幕接口格式"而不是崩溃。
List<DanmakuComment> parseDanmaku(String body) {
  final text = body.trim();
  if (text.isEmpty) return const [];
  if (text.startsWith('{') || text.startsWith('[')) return _parseJson(text);
  return _parseXml(text);
}

List<DanmakuComment> _parseJson(String text) {
  Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    return const [];
  }
  final list = root is Map ? root['comments'] : root;
  if (list is! List) return const [];
  final out = <DanmakuComment>[];
  for (final raw in list) {
    if (raw is! Map) continue;
    final p = raw['p'];
    final content = raw['m'];
    if (p is! String || content is! String) continue;
    final parsed = _fromP(p, content);
    if (parsed != null) out.add(parsed);
  }
  return out;
}

/// `<d p="12.5,1,16777215,abc">文字</d>`，也认 `<d p="...">` 之外的多行内容。
List<DanmakuComment> _parseXml(String text) {
  final pattern = RegExp(
    r'<d\s+p="([^"]*)"\s*>([\s\S]*?)</d>',
    caseSensitive: false,
  );
  final out = <DanmakuComment>[];
  for (final m in pattern.allMatches(text)) {
    final p = m.group(1) ?? '';
    final content = _unescape(m.group(2) ?? '').trim();
    if (content.isEmpty) continue;
    final parsed = _fromP(p, content);
    if (parsed != null) out.add(parsed);
  }
  return out;
}

DanmakuComment? _fromP(String p, String content) {
  final parts = p.split(',');
  if (parts.length < 3) return null;
  final seconds = double.tryParse(parts[0]);
  if (seconds == null || seconds < 0) return null;
  final mode = int.tryParse(parts[1]) ?? DanmakuComment.scroll;
  final color = int.tryParse(parts[2]) ?? 0xFFFFFF;
  return DanmakuComment(
    timeMs: (seconds * 1000).round(),
    text: content,
    mode: mode,
    color: color & 0xFFFFFF,
  );
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// 从剧集标题里取集数。
///
/// 源站给的是「第 12 集」「EP12」「12」这类写法；取不到数字就返回 `null`，
/// 上层会退回"按文件名匹配"，而不是猜一个集数。
int? episodeNumber(String label) {
  final digits = RegExp(r'\d+').allMatches(label);
  for (final m in digits) {
    final n = int.tryParse(m.group(0)!);
    if (n != null && n > 0) return n;
  }
  return null;
}
