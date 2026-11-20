import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Host-side management of the catvod (猫源) Node runtime.
///
/// The original ships a `node.exe` plus a small `cat_host.js` bridge and drives
/// it over an HTTP control port guarded by a token. Each source bundle runs in
/// its own worker thread and starts a fastify server whose port is handed back
/// through `/load`. This class reproduces that protocol so the app can load,
/// query and unload a 猫源 (a `js`-type source).
///
/// It never throws: problems surface through the returned results so callers
/// can show an honest message instead of crashing.
class CatHost {
  CatHost({
    required this.nodePath,
    required this.hostScript,
    this.tmpDir,
    this.messagePort = 0,
  });

  /// Absolute path to the embedded `node.exe`.
  final String nodePath;

  /// Absolute path to the rewritten `cat_host.js`.
  final String hostScript;

  /// Where the source writes its own data/db. Falls back to the OS temp dir.
  final String? tmpDir;

  /// Port the source forwards `messageToDart` events to (0 = none).
  final int messagePort;

  Process? _process;
  String? _token;
  int? _controlPort;
  bool _stopping = false;

  bool get isRunning => _process != null;

  /// Starts the host and waits until `/ping` answers.
  ///
  /// [controlPort] 0 lets the OS pick a free port (recommended); a fixed port is
  /// useful in tests. Returns the control port on success, or throws on failure.
  Future<int> start({int controlPort = 0}) async {
    if (_process != null) return _controlPort!;
    _stopping = false;
    _token = _randomToken();
    final actualPort = controlPort == 0 ? await _freePort() : controlPort;

    final process = await Process.start(
      nodePath,
      [
        hostScript,
        '$actualPort',
        _token!,
        tmpDir ?? Directory.systemTemp.path,
        'stdin',
        '$messagePort',
      ],
      mode: ProcessStartMode.normal,
    );
    _process = process;
    _controlPort = actualPort;

    // Drain stdout/stderr so the child never blocks on a full pipe.
    process.stdout.listen((_) {});
    process.stderr.listen((_) {});
    process.exitCode.then((_) {
      if (!_stopping) _process = null;
    });

    // Wait for the host to come up.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final ping = await _post('/ping', {});
      if (ping != null && ping['ok'] == true) return actualPort;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await stop();
    throw const CatHostException('宿主启动超时');
  }

  /// Loads a source bundle (a directory holding `index.js`).
  ///
  /// Returns the source's HTTP port, or throws if the source failed to boot.
  Future<int> loadSource(String id, String dir) async {
    final reply = await _post('/load', {'id': id, 'dir': dir});
    final port = reply?['port'];
    if (port is int) return port;
    throw CatHostException('加载源失败：${reply?['error'] ?? '无端口回传'}');
  }

  Future<void> unloadSource(String id) async {
    await _post('/unload', {'id': id});
  }

  Future<void> stop() async {
    _stopping = true;
    final process = _process;
    _process = null;
    if (process == null) return;
    // Desktop host watches stdin; closing it makes it exit cleanly.
    process.stdin.close();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on Object {
      process.kill(ProcessSignal.sigkill);
    }
  }

  Future<Map<String, dynamic>?> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final port = _controlPort;
    final token = _token;
    if (port == null || token == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .postUrl(Uri.parse('http://127.0.0.1:$port$path'))
          .timeout(const Duration(seconds: 5));
      request.headers.set('content-type', 'application/json');
      request.headers.set('x-token', token);
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) return null;
      final text = await utf8.decodeStream(response);
      if (text.isEmpty) return const {};
      return jsonDecode(text) as Map<String, dynamic>;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

class CatHostException implements Exception {
  const CatHostException(this.message);

  final String message;

  @override
  String toString() => message;
}
