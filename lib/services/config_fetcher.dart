import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import 'site_parser.dart';

/// Result of pulling a config address over HTTP.
class FetchResult {
  const FetchResult({
    this.sites = const [],
    this.latencyMs = 0,
    this.error,
    this.note,
  });

  const FetchResult.failure(String message, {this.latencyMs = 0})
    : sites = const [],
      error = message,
      note = null;

  final List<SiteInfo> sites;

  /// Round-trip time of the request that produced [sites].
  final int latencyMs;

  /// Non-null when nothing usable came back.
  final String? error;

  /// Extra context worth showing even on success ("这是 js 源…").
  final String? note;

  bool get ok => error == null && sites.isNotEmpty;
}

/// A 32- or 64-char hex file is an `.md5` checksum, not the config itself.
final _checksum = RegExp(r'^[0-9a-fA-F]{32}$|^[0-9a-fA-F]{64}$');

const _maxBytes = 8 * 1024 * 1024;

/// Fetches a TVBox / catvod config and parses it into sites.
///
/// This is the networked half of 添加资源 that the paste form could not do: the
/// original pulls the same document over HTTP. Two shapes are handled honestly:
///
///   * a JSON document (or a per-line `名称$地址` text) is parsed straight into
///     sites, exactly like a paste;
///   * an `.md5` address returns only a checksum -- the config itself sits at the
///     same URL without the suffix, so one retry is made;
///   * a JS bundle (the `js` source type) cannot be parsed here: its sites are
///     `meta:{…}` blocks that only a spider host can enumerate. That is reported
///     as a note rather than as a failure of the source.
///
/// Never throws: every problem comes back as [FetchResult.error].
Future<FetchResult> fetchConfig(
  String url, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final target = url.trim();
  if (target.isEmpty) return const FetchResult.failure('地址为空');
  final first = await _get(target, timeout: timeout);
  if (first.error != null) {
    return FetchResult.failure(first.error!, latencyMs: first.latencyMs);
  }

  var text = first.body!;
  final trimmed = text.trim();

  // `.md5` endpoints return the hash of the real config. Try the URL once more
  // without the suffix, which is where the document lives.
  if (_checksum.hasMatch(trimmed) && target.toLowerCase().endsWith('.md5')) {
    final real = target.substring(0, target.length - 4);
    final second = await _get(real, timeout: timeout);
    if (second.error != null) {
      return FetchResult.failure(
        '${second.error}（地址是 .md5 校验文件，去后缀再试也失败）',
        latencyMs: first.latencyMs + second.latencyMs,
      );
    }
    text = second.body!;
  }

  final parsed = parseConfig(text);
  if (parsed.ok && parsed.count > 0) {
    return FetchResult(
      sites: parsed.sites,
      latencyMs: first.latencyMs,
      note: parsed.silenced > 0 ? '其中 ${parsed.silenced} 个默认不参与搜索' : null,
    );
  }

  if (_looksLikeJs(text)) {
    return FetchResult(
      latencyMs: first.latencyMs,
      note: '这是 js 源（站点写在脚本里），需要 spider 宿主才能列出站点',
    );
  }

  return FetchResult.failure(
    parsed.error ?? '没有解析到站点',
    latencyMs: first.latencyMs,
  );
}

/// Pulls a plain-text document -- a live list (m3u / txt) rather than a config.
///
/// A live list is not a config: it has no `sites`, so [fetchConfig] would report
/// "没有解析到站点" for a file that is perfectly good. Same transport, same
/// errors, just the body handed back for the caller to count channels in.
Future<({String? text, int latencyMs, String? error})> fetchPlainText(
  String url, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final target = url.trim();
  if (target.isEmpty) {
    return (text: null, latencyMs: 0, error: '地址为空');
  }
  final response = await _get(target, timeout: timeout);
  return (
    text: response.body,
    latencyMs: response.latencyMs,
    error: response.error,
  );
}

class _Response {
  const _Response({this.body, this.error, this.latencyMs = 0});

  final String? body;
  final String? error;
  final int latencyMs;
}

Future<_Response> _get(
  String url, {
  required Duration timeout,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    return const _Response(error: '地址格式不对');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return const _Response(error: '只支持 http / https 地址');
  }

  final client = HttpClient()..connectionTimeout = timeout;
  final watch = Stopwatch()..start();
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) LaiCuiBa/0.1',
    );
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    final response = await request.close().timeout(timeout);

    if (response.statusCode != HttpStatus.ok) {
      return _Response(
        error: 'HTTP ${response.statusCode}',
        latencyMs: watch.elapsedMilliseconds,
      );
    }

    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBytes) {
        return _Response(
          error: '内容超过 ${_maxBytes ~/ (1024 * 1024)} MB，不像配置文档',
          latencyMs: watch.elapsedMilliseconds,
        );
      }
    }
    return _Response(
      body: _decode(bytes),
      latencyMs: watch.elapsedMilliseconds,
    );
  } on TimeoutException {
    return _Response(
      error: '请求超时（${timeout.inSeconds} 秒）',
      latencyMs: watch.elapsedMilliseconds,
    );
  } on SocketException catch (error) {
    return _Response(
      error: '连不上：${error.osError?.message ?? error.message}',
      latencyMs: watch.elapsedMilliseconds,
    );
  } on Object catch (error) {
    return _Response(
      error: '请求失败：$error',
      latencyMs: watch.elapsedMilliseconds,
    );
  } finally {
    client.close(force: true);
  }
}

/// UTF-8 first (configs are usually JSON), GB18030-ish bytes fall back to
/// latin1 so the structural characters stay readable for the parser.
String _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

bool _looksLikeJs(String text) {
  final head = text.trimLeft();
  if (head.startsWith('{') || head.startsWith('[')) return false;
  return head.contains('meta:{') ||
      head.contains('function') ||
      head.contains('require(') ||
      head.contains('module.exports');
}
