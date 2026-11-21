import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Host-side management of a TVBox **script** runtime.
///
/// Two runtimes share this bus because they answer the same protocol: one line
/// of JSON per request on stdin, one line per reply on stdout. Python does it
/// with `py_host.py`, TVBox-style `.js` sites with `js_site_host.js`; both hand
/// back the source's own response body as a string, i.e. exactly the JSON TVBox
/// would have given its UI.
///
/// There is no control port — the pipe *is* the protocol, so two sources cannot
/// collide on a port and nothing is exposed to the network.
///
/// Nothing here throws at construction time; failures surface from [start] and
/// from the individual calls as [SourceHostException].
class SourceHost {
  SourceHost({
    required this.executable,
    required this.script,
    required this.label,
    this.callTimeout = const Duration(seconds: 25),
    this.environment = const {},
  });

  /// Absolute path to the runtime binary (`python.exe` / `node.exe`).
  final String executable;

  /// Absolute path to the bridge script this class drives.
  final String script;

  /// How the runtime is named in error messages ("Python", "js").
  final String label;

  /// A source that hangs must not hang the UI; every call is bounded.
  final Duration callTimeout;

  /// Extra environment for the child. `js_site_host.js` uses it to keep its
  /// `local` store inside the app's data dir instead of next to the runtime.
  final Map<String, String> environment;

  Process? _process;
  int _nextId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  /// The last handful of stderr lines, kept so a failed call can quote what the
  /// source printed instead of just "exit code 1".
  final List<String> _log = [];
  bool _stopping = false;

  bool get isRunning => _process != null;

  /// The tail of the child's stderr, newest last.
  String get recentLog => _log.join('\n');

  /// Launches the runtime and waits for `ping` to answer.
  ///
  /// [dartPort] is where the app's own HTTP server listens; sources reach it
  /// through `self.getProxyUrl()` / `getProxyUrl()` and `setCache()`.
  Future<void> start({int dartPort = 0}) async {
    if (_process != null) return;
    _stopping = false;
    final process = await Process.start(
      executable,
      [script],
      mode: ProcessStartMode.normal,
      environment: environment.isEmpty ? null : environment,
    );
    _process = process;

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onError: (Object _) {});
    process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        if (line.trim().isEmpty) return;
        _log.add(line);
        if (_log.length > 20) _log.removeAt(0);
      },
      onError: (Object _) {},
    );
    process.exitCode.then((_) {
      if (!_stopping) _process = null;
    });

    final version = await ping();
    if (version == null || version.isEmpty) {
      await stop();
      throw SourceHostException(
        '$label 宿主没有应答${recentLog.isEmpty ? '' : '：$recentLog'}',
      );
    }
    if (dartPort > 0) {
      await _send('port', {'port': dartPort});
    }
  }

  /// Returns the runtime version, or null when the host is not up.
  Future<String?> ping() async {
    try {
      final reply = await _send('ping', {}, timeout: const Duration(seconds: 8));
      return '${reply['result'] ?? ''}';
    } on Object {
      return null;
    }
  }

  /// Calls one of the source's entry points and returns its response body.
  ///
  /// [method] is a TVBox verb: `home` / `category` / `detail` / `search` /
  /// `player` / `live` / `init`. [args] is passed through as the argument list
  /// the source will receive (padded or trimmed to its own signature).
  Future<String> call({
    required String key,
    required String path,
    required String method,
    String ext = '',
    List<Object?> args = const [],
  }) async {
    final reply = await _send('call', {
      'key': key,
      'path': path,
      'ext': ext,
      'method': method,
      'args': jsonEncode(args),
    });
    final result = reply['result'];
    return result is String ? result : (result == null ? '' : '$result');
  }

  /// Lists the platforms a script file declares in its module-level `SITES`.
  ///
  /// An aggregate source is one file that fronts several platforms; each one is
  /// selected at call time through `ext`, so the config has to know their names
  /// before anything can be played. An empty list means "this is an ordinary
  /// single-site source", not an error.
  Future<List<SourceSubSite>> sites({required String path}) async {
    final reply = await _send(
      'sites',
      {'path': path},
      timeout: const Duration(seconds: 20),
    );
    final result = reply['result'];
    if (result is! List) return const [];
    return [
      for (final raw in result)
        if (raw is Map && '${raw['key'] ?? ''}'.trim().isNotEmpty)
          SourceSubSite(
            key: '${raw['key']}'.trim(),
            name: '${raw['name'] ?? raw['key']}'.trim(),
            ext: raw['ext'],
          ),
    ];
  }

  /// Asks the source to answer a `/proxy?do=…` request. The body comes back
  /// base64 so binary content (playlists, images, segments) survives the pipe.
  ///
  /// [timeout] is separate from [callTimeout] because a proxy hop usually means
  /// the source is fetching a remote object first, which costs more time than
  /// parsing its own JSON.
  Future<SourceProxyResponse> proxy(
    Map<String, dynamic> params, {
    Duration? timeout,
  }) async {
    final reply = await _send(
      'proxy',
      {'params': jsonEncode(params)},
      timeout: timeout,
    );
    final result = reply['result'];
    if (result is! Map) {
      throw const SourceHostException('代理返回了非对象结果');
    }
    return SourceProxyResponse(
      status: (result['status'] as num?)?.toInt() ?? 502,
      mime: '${result['mime'] ?? 'text/plain'}',
      body: base64Decode('${result['body'] ?? ''}'),
      headers: _headersOf(result['headers']),
    );
  }

  /// Drops the source instance so the next call re-runs its `init`.
  Future<void> release(String key) async {
    if (_process == null) return;
    try {
      await _send('release', {'key': key}, timeout: const Duration(seconds: 8));
    } on Object {
      // 卸载失败不值得打扰调用方：进程还活着，下一次加载会重来。
    }
  }

  Future<void> stop() async {
    _stopping = true;
    final process = _process;
    _process = null;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(SourceHostException('$label 宿主已停止'));
      }
    }
    _pending.clear();
    if (process == null) return;
    // The host reads stdin until EOF: closing it is the clean shutdown signal.
    await process.stdin.close().catchError((Object _) {});
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on Object {
      process.kill(ProcessSignal.sigkill);
    }
  }

  Future<Map<String, dynamic>> _send(
    String op,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    final process = _process;
    if (process == null) throw SourceHostException('$label 宿主没有启动');

    final id = ++_nextId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    try {
      process.stdin.writeln(jsonEncode({'id': id, 'op': op, ...body}));
      await process.stdin.flush().catchError((Object _) {});
      final reply = await completer.future.timeout(timeout ?? callTimeout);
      if (reply['ok'] == true) return reply;
      throw SourceHostException('${reply['error'] ?? '调用失败'}');
    } on TimeoutException {
      throw SourceHostException(
        '源没有在 ${(timeout ?? callTimeout).inSeconds} 秒内回应',
      );
    } finally {
      _pending.remove(id);
    }
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    Map<String, dynamic> reply;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return;
      reply = Map<String, dynamic>.from(decoded);
    } on FormatException {
      // Not protocol traffic (a source printing to the real stdout, say).
      _log.add(line);
      return;
    }
    final id = reply['id'];
    final completer = id is int ? _pending[id] : null;
    if (completer != null && !completer.isCompleted) completer.complete(reply);
  }

  static Map<String, String> _headersOf(Object? raw) {
    if (raw is Map) {
      return {
        for (final entry in raw.entries) '${entry.key}': '${entry.value}',
      };
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return {
            for (final entry in decoded.entries) '${entry.key}': '${entry.value}',
          };
        }
      } on FormatException {
        return const {};
      }
    }
    return const {};
  }
}

/// One platform an aggregate script source declares in `SITES`.
class SourceSubSite {
  const SourceSubSite({required this.key, required this.name, this.ext});

  /// The platform id the source itself uses (`spider.call(platform, …)`).
  final String key;
  final String name;

  /// Extra per-platform `init` parameters, when `SITES` carries them.
  final Object? ext;
}

/// One `/proxy` answer: what the source wants the player (or an image view) to
/// receive.
class SourceProxyResponse {
  const SourceProxyResponse({
    required this.status,
    required this.mime,
    required this.body,
    this.headers = const {},
  });

  final int status;
  final String mime;
  final List<int> body;
  final Map<String, String> headers;
}

class SourceHostException implements Exception {
  const SourceHostException(this.message);

  final String message;

  @override
  String toString() => message;
}
