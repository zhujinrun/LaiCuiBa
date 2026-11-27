import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'hls_ad_filter.dart';

/// Loopback HTTP endpoint that serves ad-free HLS playlists.
///
/// libmpv has no playlist rewrite hook, so the player opens
/// `http://127.0.0.1:<port>/hls?u=...` instead of the source URL. Only playlist
/// text goes through here; the remaining TS segments are rewritten to absolute
/// addresses and fetched by mpv directly, with the original headers.
class HlsCleanProxy {
  HlsCleanProxy._();

  static final HlsCleanProxy instance = HlsCleanProxy._();

  static const _filter = HlsAdFilter();

  final HttpClient _client = HttpClient()
    ..idleTimeout = const Duration(seconds: 15);
  HttpServer? _server;
  Future<int>? _starting;

  /// Returns a local URL for [url], or [url] unchanged when it is not HLS or
  /// the listener could not be started.
  Future<String> wrap(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !url.toLowerCase().contains('.m3u8')) {
      return url;
    }
    if (uri.host == '127.0.0.1' && uri.path == '/hls') return url;
    try {
      return _localUrl(url, await _port(), headers);
    } on Object catch (e) {
      stderr.writeln('LcbHls: proxy unavailable, playing the original URL: $e');
      return url;
    }
  }

  Future<int> _port() => _starting ??= _start();

  Future<int> _start() async {
    final running = _server;
    if (running != null) return running.port;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle, onError: (Object _) {});
    return server.port;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.uri.path != '/hls') {
        await _reply(request, 404, 'text/plain; charset=utf-8', 'not found');
        return;
      }
      final upstream = Uri.tryParse(request.uri.queryParameters['u'] ?? '');
      if (upstream == null ||
          (upstream.scheme != 'http' && upstream.scheme != 'https')) {
        await _reply(request, 400, 'text/plain; charset=utf-8', 'bad url');
        return;
      }
      final headers = _decodeHeaders(request.uri.queryParameters['h']);
      final upstreamRequest = await _client.getUrl(upstream);
      upstreamRequest.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      for (final entry in headers.entries) {
        if (_skipHeader(entry.key)) continue;
        try {
          upstreamRequest.headers.set(entry.key, entry.value);
        } on Object {
          // A source may hand us a header name mpv accepted but Dart refuses.
        }
      }
      final response = await upstreamRequest.close();
      final bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      if (response.statusCode != 200) {
        await _reply(
          request,
          response.statusCode,
          'text/plain; charset=utf-8',
          utf8.decode(bytes, allowMalformed: true),
        );
        return;
      }

      final text = utf8.decode(bytes, allowMalformed: true);
      final mime = response.headers.contentType?.toString() ?? '';
      if (!mime.contains('mpegurl') && !text.trimLeft().startsWith('#EXTM3U')) {
        await _reply(
          request,
          200,
          mime.isEmpty ? 'application/octet-stream' : mime,
          bytes,
        );
        return;
      }

      final port = await _port();
      final cleaned = _filter.clean(
        text,
        source: upstream,
        rewritePlaylist: (uri) => _localUrl(uri.toString(), port, headers),
      );
      stderr.writeln(
        'LcbHls: cleaned ${upstream.path} (${bytes.length} -> ${cleaned.length} bytes)',
      );
      await _reply(
        request,
        200,
        'application/vnd.apple.mpegurl; charset=utf-8',
        cleaned,
      );
    } on Object catch (e) {
      stderr.writeln('LcbHls: failed to clean playlist: $e');
      try {
        await _reply(request, 502, 'text/plain; charset=utf-8', '$e');
      } on Object {
        // The client already went away.
      }
    }
  }

  static String _localUrl(String url, int port, Map<String, String> headers) {
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      path: '/hls',
      queryParameters: {
        'u': url,
        'h': base64Url.encode(utf8.encode(jsonEncode(headers))),
      },
    ).toString();
  }

  static Map<String, String> _decodeHeaders(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const {};
    try {
      final decoded = jsonDecode(utf8.decode(base64Url.decode(encoded)));
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } on Object {
      return const {};
    }
  }

  static bool _skipHeader(String name) {
    switch (name.toLowerCase()) {
      case 'host':
      case 'content-length':
      case 'transfer-encoding':
      case 'connection':
      case 'content-encoding':
        return true;
      default:
        return false;
    }
  }

  static Future<void> _reply(
    HttpRequest request,
    int status,
    String mime,
    Object body,
  ) async {
    final response = request.response;
    response.statusCode = status;
    response.headers.set(HttpHeaders.contentTypeHeader, mime);
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    if (body is List<int>) {
      response.add(body);
    } else {
      response.write(body);
    }
    await response.close();
  }
}
