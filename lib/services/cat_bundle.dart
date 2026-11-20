import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

/// Downloads and stages a catvod (猫源) bundle, mirroring the original's
/// subscription model.
///
/// A bundle is a directory holding `index.js` (the spider code) plus
/// `index.config.js` (theme/config). The subscription URL points at a `.md5`
/// file whose body is the checksum of the real `index.js`; the bundle is only
/// re-downloaded when that checksum changes, so the app does not re-fetch 9 MB
/// every launch.
///
/// Everything is inert and never throws: failures come back as a result with a
/// message the caller can show.
class CatBundle {
  CatBundle({required this.rootDir, HttpClient? client})
    : _client = client ?? HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);

  /// Where bundles live, e.g. `<appdata>/LaiCuiBa/LaiCuiBa/cat`.
  final Directory rootDir;
  final HttpClient _client;

  static const _maxBytes = 16 * 1024 * 1024;

  /// Resolves (and downloads if needed) the bundle for [md5Url], returning the
  /// directory that now holds `index.js`. Idempotent: a matching cached copy
  /// is reused without network.
  Future<BundleResult> ensure(String md5Url) async {
    final base = _stripMd5(md5Url);
    final id = _bundleId(base);
    final dir = Directory(p.join(rootDir.path, id));

    final indexJs = File(p.join(dir.path, 'index.js'));
    final configJs = File(p.join(dir.path, 'index.config.js'));

    final remoteMd5 = await _fetchText(md5Url);
    if (remoteMd5.error != null) {
      // If we already have a cached bundle, a transient md5 failure should not
      // block playback: reuse what is on disk.
      if (indexJs.existsSync()) {
        return BundleResult(dir.path, note: 'md5 拉取失败，用本地缓存（${remoteMd5.error}）');
      }
      return BundleResult.failure(remoteMd5.error!);
    }
    final want = remoteMd5.text!.trim();
    if (want.isEmpty) return const BundleResult.failure('订阅地址返回空 md5');

    if (indexJs.existsSync()) {
      final have = _md5Of(indexJs);
      if (have == want) return BundleResult(dir.path);
    }

    // Download the bundle into a temp dir, then swap it in.
    await dir.create(recursive: true);
    final tmp = Directory(p.join(dir.path, '.tmp-${DateTime.now().millisecondsSinceEpoch}'));
    await tmp.create(recursive: true);
    final js = await _fetchBytes('$base/index.js');
    final cfg = await _fetchBytes('$base/index.config.js');
    if (js.error != null) {
      await tmp.delete(recursive: true);
      if (indexJs.existsSync()) {
        return BundleResult(dir.path, note: '下载失败，用本地缓存（${js.error}）');
      }
      return BundleResult.failure(js.error!);
    }
    await File(p.join(tmp.path, 'index.js')).writeAsBytes(js.bytes!);
    if (cfg.error == null) {
      await File(p.join(tmp.path, 'index.config.js')).writeAsBytes(cfg.bytes!);
    }
    // Verify the download matches the advertised checksum before swapping.
    if (_md5Of(File(p.join(tmp.path, 'index.js'))) != want) {
      await tmp.delete(recursive: true);
      return const BundleResult.failure('下载的 index.js 校验和不匹配');
    }
    if (indexJs.existsSync()) await indexJs.delete();
    if (configJs.existsSync()) await configJs.delete();
    await File(p.join(tmp.path, 'index.js')).rename(indexJs.path);
    final tmpCfg = File(p.join(tmp.path, 'index.config.js'));
    if (tmpCfg.existsSync()) await tmpCfg.rename(configJs.path);
    await tmp.delete(recursive: true);
    return BundleResult(dir.path);
  }

  /// A stable directory name for a bundle URL, hashing the host+path.
  String _bundleId(String base) {
    final bytes = utf8.encode(base);
    var hash = 0x811c9dc5;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String _stripMd5(String url) =>
      url.toLowerCase().endsWith('.md5') ? url.substring(0, url.length - 4) : url;

  Future<_Bytes> _fetchBytes(String url) async {
    try {
      final uri = Uri.parse(url);
      final request = await _client.getUrl(uri).timeout(const Duration(seconds: 60));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) LaiCuiBa/0.1',
      );
      final response = await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode != HttpStatus.ok) {
        return _Bytes(error: 'HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBytes) {
          return const _Bytes(error: '内容过大');
        }
      }
      return _Bytes(bytes: bytes);
    } on TimeoutException {
      return const _Bytes(error: '下载超时');
    } on SocketException catch (e) {
      return _Bytes(error: '连不上：${e.osError?.message ?? e.message}');
    } on Object catch (e) {
      return _Bytes(error: '下载失败：$e');
    }
  }

  Future<_Bytes> _fetchText(String url) async {
    final result = await _fetchBytes(url);
    if (result.error != null) return result;
    return _Bytes(text: utf8.decode(result.bytes!, allowMalformed: true).trim());
  }

  /// MD5 over the file bytes, hex-encoded (32 hex chars), matching the source's
  /// `.md5` checksum file.
  static String _md5Of(File file) =>
      crypto.md5.convert(file.readAsBytesSync()).toString();
}

class BundleResult {
  const BundleResult(this.dir, {this.note, this.error});

  const BundleResult.failure(String message)
    : dir = '',
      note = null,
      error = message;

  final String dir;
  final String? note;
  final String? error;

  bool get ok => error == null && dir.isNotEmpty;
}

class _Bytes {
  const _Bytes({this.bytes, this.text, this.error});

  final List<int>? bytes;
  final String? text;
  final String? error;
}
