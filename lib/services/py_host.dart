import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Host-side management of the TVBox (Python) source runtime.
///
/// The original app ships a CPython distribution plus a small `py_host.py`
/// bridge: one line of JSON per request on stdin, one line per reply on stdout.
/// Unlike the 猫源 host there is no control port — the pipe *is* the protocol,
/// so two sources cannot collide on a port and nothing is exposed to the
/// network.
///
/// The reply to `call` is the source's own response body as a string, i.e. the
/// exact JSON TVBox would have handed to its UI. Mapping it to [MediaItem] is
/// the caller's job (`services/tvbox_source.dart`), which keeps this class
/// free of model knowledge.
///
/// Nothing here throws at construction time; failures surface from [start] and
/// from the individual calls as [PyHostException].
class PyHost {
  PyHost({
    required this.pythonPath,
    required this.hostScript,
    this.callTimeout = const Duration(seconds: 25),
  });

  /// Absolute path to the embedded `python.exe`.
  final String pythonPath;

  /// Absolute path to `py_host.py`. Its directory is put on `sys.path`, so the
  /// `base/` package next to it resolves for every source.
  final String hostScript;

  /// A source that hangs must not hang the UI; every call is bounded.
  final Duration callTimeout;

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

  /// Launches the interpreter and waits for `ping` to answer.
  ///
  /// [dartPort] is where the app's own HTTP server listens; sources reach it
  /// through `self.getProxyUrl()` and `self.setCache()`.
  Future<void> start({int dartPort = 0}) async {
    if (_process != null) return;
    _stopping = false;
    final process = await Process.start(
      pythonPath,
      [hostScript],
      mode: ProcessStartMode.normal,
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
      throw PyHostException('Python 宿主没有应答${recentLog.isEmpty ? '' : '：$recentLog'}');
    }
    if (dartPort > 0) {
      await _send('port', {'port': dartPort});
    }
  }

  /// Returns the interpreter version, or null when the host is not up.
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

  /// Asks the source to answer a `/proxy?do=…` request. The body comes back
  /// base64 so binary content (playlists, images, segments) survives the pipe.
  Future<PyProxyResponse> proxy(Map<String, dynamic> params) async {
    final reply = await _send('proxy', {'params': jsonEncode(params)});
    final result = reply['result'];
    if (result is! Map) {
      throw const PyHostException('代理返回了非对象结果');
    }
    return PyProxyResponse(
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
        pending.completeError(const PyHostException('宿主已停止'));
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
    if (process == null) throw const PyHostException('宿主没有启动');

    final id = ++_nextId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    try {
      process.stdin.writeln(jsonEncode({'id': id, 'op': op, ...body}));
      await process.stdin.flush().catchError((Object _) {});
      final reply = await completer.future.timeout(timeout ?? callTimeout);
      if (reply['ok'] == true) return reply;
      throw PyHostException('${reply['error'] ?? '调用失败'}');
    } on TimeoutException {
      throw PyHostException('源没有在 ${(timeout ?? callTimeout).inSeconds} 秒内回应');
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
        for (final entry in raw.entries)
          '${entry.key}': '${entry.value}',
      };
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return {
            for (final entry in decoded.entries)
              '${entry.key}': '${entry.value}',
          };
        }
      } on FormatException {
        return const {};
      }
    }
    return const {};
  }
}

/// One `/proxy` answer: what the source wants the player (or an image view) to
/// receive.
class PyProxyResponse {
  const PyProxyResponse({
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

class PyHostException implements Exception {
  const PyHostException(this.message);

  final String message;

  @override
  String toString() => message;
}
