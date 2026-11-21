import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart';
import 'local_proxy.dart';
import 'py_host.dart';
import 'tvbox_source.dart';

/// True when [api] names a Python source rather than a catvod bundle.
///
/// Only the extension is checked, because both runtimes address their sources
/// the same way otherwise (`http(s)://…/main.py` is a normal TVBox api, and a
/// config written on Windows may carry a backslash path).
bool isPyApi(String api) {
  final address = api.trim().toLowerCase();
  if (address.isEmpty) return false;
  final path = address.split('?').first;
  return path.endsWith('.py');
}

/// What the rest of the app asks of the Python side.
///
/// Kept as an interface so the store can be tested without an interpreter: a
/// test hands in a fake that returns a [TvBoxSource] over a canned [PyHost].
abstract class PySources {
  /// A source ready to answer `home` / `category` / `search` / `detail` /
  /// `player` for one site of [source], or null when it cannot be started.
  Future<TvBoxSource?> sourceFor({
    required SourceInfo source,
    required SiteInfo site,
  });

  /// The site list with every aggregate file expanded into the platforms its
  /// `SITES` declares, or null when nothing expanded (the caller keeps the
  /// source as it is).
  Future<List<SiteInfo>?> expandSites(SourceInfo source);

  /// Why the last [sourceFor] returned null. Null once something worked.
  String? get lastError;

  Future<void> dispose();
}

/// Owns the CPython child, the app-side proxy listener, and the sources that
/// run on top of them.
///
/// Everything is lazy: a build that never opens a TVBox source never starts an
/// interpreter. The listener has to come up first because the port is part of
/// the host's contract (`self.getProxyUrl()` points at it), which is why the two
/// are created together rather than independently.
///
/// [site]'s `api` is either a local `.py` path (an imported source) or an
/// `http(s)` URL (a site inside a TVBox config). Remote files are fetched once
/// and kept in [cacheDir] under a hash of their URL, so the second launch costs
/// no download; editing the URL yields a different hash and a fresh copy.
class PyRuntime implements PySources {
  PyRuntime({
    required this.pythonPath,
    required this.hostScript,
    required this.cacheDir,
    this.hostFactory,
  });

  final String pythonPath;
  final String hostScript;
  final Directory cacheDir;

  /// Overrides how the child is built, for tests that drive a fake host. Null
  /// means a real [PyHost] over [pythonPath] / [hostScript].
  final PyHost Function()? hostFactory;

  /// A source file larger than this is not a source. Bounded so a URL that
  /// points at a video cannot fill the disk.
  static const maxSourceBytes = 8 * 1024 * 1024;

  /// How long a failed start is remembered before it is worth retrying. Booting
  /// an interpreter that is missing fails the same way every time, and a search
  /// page fires a call per keystroke.
  static const _retryAfter = Duration(seconds: 5);

  PyHost? _host;
  LocalProxyServer? _server;
  Future<PyHost?>? _starting;
  DateTime? _failedAt;
  String? _lastError;

  /// One [TvBoxSource] per `source|site`, so the host keeps its loaded module
  /// (and the login token inside it) instead of re-running `init` every call.
  final Map<String, TvBoxSource> _sources = {};

  @override
  String? get lastError => _lastError;

  /// The port the source sees as `127.0.0.1:<port>`. 0 when not running.
  int get port => _server?.port ?? 0;

  bool get isRunning => _host != null;

  @override
  Future<TvBoxSource?> sourceFor({
    required SourceInfo source,
    required SiteInfo site,
  }) async {
    final path = await _localFileFor(site.api);
    if (path == null) return null;
    final host = await _ensureHost();
    if (host == null) return null;

    final key = '${source.id}|${site.key}';
    final existing = _sources[key];
    if (existing != null && existing.path == path) return existing;
    // The api changed under the same key: the loaded module is the old file, so
    // drop it before the next call re-runs init.
    if (existing != null) await host.release(key);

    final created = TvBoxSource(
      host: host,
      key: key,
      path: path,
      ext: site.ext,
      siteKey: site.key,
    );
    _sources[key] = created;
    _lastError = null;
    return created;
  }

  @override
  Future<List<SiteInfo>?> expandSites(SourceInfo source) async {
    final declared = source.sites.isNotEmpty
        ? source.sites
        : source.type == 'py'
        ? [SiteInfo(key: source.id, name: source.name, api: source.url)]
        : const <SiteInfo>[];
    if (declared.isEmpty) return null;

    var changed = false;
    final out = <SiteInfo>[];
    for (final site in declared) {
      final platforms = await _platformsOf(site);
      if (platforms == null) {
        out.add(site);
        continue;
      }
      changed = true;
      for (final platform in platforms) {
        out.add(
          SiteInfo(
            key: _uniqueKey(out, platform.key, site.key),
            name: platform.name,
            api: site.api,
            ext: _platformExt(site.ext, platform),
            enabled: site.enabled,
          ),
        );
      }
    }
    return changed ? out : null;
  }

  /// The platforms [site]'s file declares, or null when it is not an aggregate
  /// source (or cannot be read, in which case 检测 reports the real failure).
  ///
  /// A site already carrying `__aggregatePlatform` is one of its own children:
  /// asking again would expand it forever.
  Future<List<PySubSite>?> _platformsOf(SiteInfo site) async {
    if (!isPyApi(site.api)) return null;
    if (_aggregatePlatform(site.ext) != null) return null;
    if (!_injectableExt(site.ext)) return null;
    final path = await _localFileFor(site.api);
    if (path == null) return null;
    final host = await _ensureHost();
    if (host == null) return null;
    try {
      final platforms = await host.sites(path: path);
      return platforms.isEmpty ? null : platforms;
    } on Object {
      return null;
    }
  }

  /// The `ext` a child platform is called with: the site's own parameters plus
  /// the platform selector, plus whatever `SITES` attached to that platform.
  static String _platformExt(String ext, PySubSite platform) {
    final base = <String, dynamic>{};
    final raw = ext.trim();
    if (raw.startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) base.addAll(Map<String, dynamic>.from(decoded));
      } on FormatException {
        // Unreachable: [_injectableExt] already rejected it.
      }
    }
    base['__aggregatePlatform'] = platform.key;
    final extra = platform.ext;
    if (extra is Map) base.addAll(Map<String, dynamic>.from(extra));
    return jsonEncode(base);
  }

  /// Site keys are how history rows and detail lookups find their way back, so
  /// two files offering the same platform name must not collide.
  static String _uniqueKey(List<SiteInfo> taken, String key, String file) {
    final used = taken.map((site) => site.key).toSet();
    if (!used.contains(key)) return key;
    var candidate = '$file:$key';
    var suffix = 2;
    while (used.contains(candidate)) {
      candidate = '$file:$key#${suffix++}';
    }
    return candidate;
  }

  /// Whether `ext` can carry the platform selector: empty, or a JSON object.
  /// A non-empty free-form string is some source's own `init` parameter, and
  /// overwriting it to inject ours would break that source.
  static bool _injectableExt(String ext) {
    final raw = ext.trim();
    if (raw.isEmpty) return true;
    if (!raw.startsWith('{')) return false;
    try {
      return jsonDecode(raw) is Map;
    } on FormatException {
      return false;
    }
  }

  static String? _aggregatePlatform(String ext) {
    final raw = ext.trim();
    if (!raw.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final value = '${decoded['__aggregatePlatform'] ?? ''}'.trim();
      return value.isEmpty ? null : value;
    } on FormatException {
      return null;
    }
  }

  /// Drops a site's loaded module, e.g. after its api was edited.
  Future<void> forget(String sourceId, String siteKey) async {
    final key = '$sourceId|$siteKey';
    final source = _sources.remove(key);
    if (source == null) return;
    final host = _host;
    if (host != null) await host.release(key);
  }

  /// Restarts the interpreter. Called by 检测, which is the user saying "I fixed
  /// something, try again" after a failure was remembered.
  Future<void> restart() async {
    await dispose();
    _failedAt = null;
    _lastError = null;
  }

  Future<PyHost?> _ensureHost() async {
    final running = _host;
    if (running != null) return running;
    final failedAt = _failedAt;
    if (failedAt != null && DateTime.now().difference(failedAt) < _retryAfter) {
      return null;
    }
    return _starting ??= _startHost();
  }

  Future<PyHost?> _startHost() async {
    LocalProxyServer? server;
    PyHost? host;
    try {
      host =
          hostFactory?.call() ??
          PyHost(pythonPath: pythonPath, hostScript: hostScript);
      // The listener must be up before the host is told its port; a source that
      // caches `getProxyUrl()` during `init` would otherwise keep a dead one.
      server = LocalProxyServer(hostProvider: () => host!);
      final port = await server.start();
      _server = server;
      _host = host;
      await host.start(dartPort: port);
      _failedAt = null;
      return host;
    } on Object catch (e) {
      _lastError = '$e';
      _failedAt = DateTime.now();
      _host = null;
      await host?.stop();
      await server?.stop();
      if (identical(_server, server)) _server = null;
      _starting = null;
      return null;
    }
  }

  /// Resolves a site's `api` to a file on disk, downloading a remote one once.
  Future<String?> _localFileFor(String api) async {
    final address = api.trim();
    if (address.isEmpty) {
      _lastError = '这个站点没有给出源地址';
      return null;
    }
    final lower = address.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      if (File(address).existsSync()) return address;
      _lastError = '源文件不存在：$address';
      return null;
    }

    final digest = md5.convert(utf8.encode(address)).toString();
    final target = File(p.join(cacheDir.path, '$digest.py'));
    if (target.existsSync() && target.lengthSync() > 0) return target.path;
    return _download(address, target);
  }

  Future<String?> _download(String url, File target) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    File? partial;
    IOSink? sink;
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'LaiCuiBa/1.0 (Windows NT 10.0; Win64; x64)',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        _lastError = '下载源文件失败（HTTP ${response.statusCode}）';
        return null;
      }

      await target.parent.create(recursive: true);
      partial = File('${target.path}.part');
      sink = partial.openWrite();
      var bytes = 0;
      var tooBig = false;
      await for (final chunk in response) {
        bytes += chunk.length;
        if (bytes > maxSourceBytes) {
          tooBig = true;
          break;
        }
        sink.add(chunk);
      }
      await sink.close();
      sink = null;
      if (tooBig) {
        _lastError = '源文件超过 ${maxSourceBytes ~/ (1024 * 1024)} MB，拒绝使用';
        await partial.delete();
        return null;
      }
      if (bytes == 0) {
        _lastError = '源文件是空的';
        await partial.delete();
        return null;
      }
      await partial.rename(target.path);
      partial = null;
      return target.path;
    } on Object catch (e) {
      _lastError = '下载源文件失败：$e';
      return null;
    } finally {
      await sink?.close().catchError((Object _) {});
      if (partial != null && partial.existsSync()) {
        await partial.delete().catchError((Object _) => partial!);
      }
      client.close(force: true);
    }
  }

  @override
  Future<void> dispose() async {
    _sources.clear();
    final host = _host;
    final server = _server;
    _host = null;
    _server = null;
    _starting = null;
    await host?.stop();
    await server?.stop();
  }
}
