import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'py_host.dart';

/// The app's own HTTP corner, i.e. the two addresses a Python source can reach
/// that are not the open internet.
///
/// A TVBox source does its own `requests` work; what it cannot do for itself is
/// two things only the host application can provide:
///
///   * `/proxy` — the address `self.getProxyUrl()` returns. Sources paste it
///     into image and playlist URLs, and every request that lands here is handed
///     to that source's own `localProxy(params)` (see [PyHost.proxy]). This is
///     where a referer-guarded m3u8, a signed image URL or a decrypted playlist
///     gets resolved.
///   * `/cache` — `getCache` / `setCache` / `delCache` in `base/spider.py`, a
///     key/value corner a source uses for tokens and resolved addresses.
///
/// Bound to loopback on an ephemeral port and only ever handed to the child
/// process, so nothing outside this machine can reach it.
class LocalProxyServer {
  LocalProxyServer({required this.hostProvider});

  /// Resolved per request rather than captured: the port has to be known before
  /// the host can be started, and a host that failed to start must leave the
  /// server answering 502 instead of holding a dead reference.
  final PyHost Function() hostProvider;

  HttpServer? _server;

  /// Session-scoped cache. Values are what a source chose to store — usually a
  /// token or a resolved address — so losing them across a restart only costs
  /// one extra round-trip, which is why this is not a database.
  final Map<String, String> _cache = {};

  /// Entries kept before the oldest is dropped. A source that caches per-title
  /// URLs must not grow the process without bound.
  static const maxCacheEntries = 512;

  /// Budget for one proxied request. Longer than an ordinary API call because a
  /// playlist or a poster behind a slow CDN is still a legitimate answer.
  static const proxyTimeout = Duration(seconds: 45);

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  @visibleForTesting
  Map<String, String> get debugCache => Map.unmodifiable(_cache);

  /// Binds the listener and returns the port. [port] 0 (the default) lets the
  /// OS pick one.
  Future<int> start({int port = 0}) async {
    final running = _server;
    if (running != null) return running.port;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    // A single failed request must not take the listener down with it; the
    // handler converts its own errors, this only catches a protocol-level one.
    server.listen(_handle, onError: (Object _) {});
    return server.port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      switch (request.uri.path) {
        case '/proxy':
          await _proxy(request);
        case '/cache':
          await _cacheRequest(request);
        default:
          await _write(request, 404, 'text/plain; charset=utf-8', 'not found');
      }
    } on Object catch (e) {
      // Half-written responses throw; swallow that and report when possible.
      try {
        await _write(request, 500, 'text/plain; charset=utf-8', '$e');
      } on Object {
        // The socket is gone; nothing left to say.
      }
    }
  }

  /// Hands one `/proxy?...` request to the source's own `localProxy`.
  ///
  /// The query is forwarded verbatim: `do`, `url`, `siteKey` and whatever else a
  /// source invented are its own business, and a whitelist here would silently
  /// drop the parameter that mattered.
  Future<void> _proxy(HttpRequest request) async {
    final params = <String, dynamic>{
      for (final entry in request.uri.queryParameters.entries)
        entry.key: entry.value,
    };
    try {
      final answer = await hostProvider().proxy(params, timeout: proxyTimeout);
      await _write(
        request,
        answer.status,
        answer.mime,
        answer.body,
        headers: answer.headers,
      );
    } on PyHostException catch (e) {
      await _write(
        request,
        502,
        'text/plain; charset=utf-8',
        '代理失败：${e.message}',
      );
    }
  }

  Future<void> _cacheRequest(HttpRequest request) async {
    final query = request.uri.queryParameters;
    final key = query['key'] ?? '';
    switch (query['do'] ?? 'get') {
      case 'set':
        final body = await utf8.decoder.bind(request).join();
        final fields = Uri.splitQueryString(body);
        _remember(key, fields['value'] ?? '');
        await _write(request, 200, 'text/plain; charset=utf-8', 'succeed');
      case 'del':
        await request.drain<void>();
        _cache.remove(key);
        await _write(request, 200, 'text/plain; charset=utf-8', 'succeed');
      default:
        await request.drain<void>();
        await _write(
          request,
          200,
          'text/plain; charset=utf-8',
          _cache[key] ?? '',
        );
    }
  }

  void _remember(String key, String value) {
    if (key.isEmpty) return;
    if (!_cache.containsKey(key) && _cache.length >= maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  Future<void> _write(
    HttpRequest request,
    int status,
    String mime,
    Object body, {
    Map<String, String> headers = const {},
  }) async {
    final response = request.response;
    response.statusCode = status;
    response.headers.set(HttpHeaders.contentTypeHeader, mime);
    // Proxied answers change with the source's mood; a cached copy would keep
    // serving a token that has already expired.
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    for (final entry in headers.entries) {
      // Framing headers describe the child's transfer, not ours.
      if (_skipHeader(entry.key)) continue;
      try {
        response.headers.set(entry.key, entry.value);
      } on Object {
        // A header the response refuses (a bad name, a duplicate) is not worth
        // failing the request over.
      }
    }
    if (body is List<int>) {
      response.add(body);
    } else {
      response.write(body);
    }
    await response.close();
  }

  /// Headers that describe how Python wrote the bytes, not what they are.
  /// Forwarding them makes the Dart response lie about its own body.
  static bool _skipHeader(String name) {
    switch (name.toLowerCase()) {
      case 'content-length':
      case 'transfer-encoding':
      case 'connection':
      case 'content-encoding':
        return true;
      default:
        return false;
    }
  }
}
