import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import 'media_mount.dart';
import 'source_probe.dart' show ProbeReport;

/// A WebDAV share used as a media source: AList, 群晖, 坚果云, Nextcloud, and
/// anything else that speaks `PROPFIND`.
///
/// There is no library API to consume -- a WebDAV server only knows about files
/// -- so the shape is inferred from the tree: a directory is a title (its video
/// files become 选集), a loose video file is a single 正片. Names are parsed for
/// the year and the episode number, which is all a file share ever offers.
///
/// One request per level: [library] lists the root, [detail] lists the one
/// directory that was opened. Nothing walks the whole tree, because an AList
/// root can hold thousands of entries.
class WebDavClient implements MediaMount {
  factory WebDavClient({
    required String baseUrl,
    required String username,
    required String password,
    String sourceName = '',
    HttpClient? http,
    Duration timeout = const Duration(seconds: 12),
  }) => WebDavClient._(
    baseUri: _normalize(baseUrl),
    auth: _basicAuth(username, password),
    sourceName: sourceName,
    http: http,
    ownsHttp: http == null,
    timeout: timeout,
  );

  WebDavClient._({
    required this.baseUri,
    required this.auth,
    required this.sourceName,
    required HttpClient? http,
    required bool ownsHttp,
    required this.timeout,
  }) : _http = http ?? HttpClient(),
       // ignore: prefer_initializing_formals
       _ownsHttp = ownsHttp;

  /// Root of the share, always with a trailing slash so `resolve` treats it as
  /// a directory.
  final Uri baseUri;

  /// `Basic …` header value. WebDAV has no token exchange, so the credential is
  /// kept on the client (built per request from the source) rather than in a
  /// poster record where it could be persisted by accident.
  final String auth;

  @override
  final String sourceName;

  final Duration timeout;
  final HttpClient _http;
  final bool _ownsHttp;

  @override
  Map<String, String> get playbackHeaders => {'Authorization': auth};

  /// Prefix that marks a record id as this client's. The href follows it.
  static const _dirTag = 'dav-dir|';
  static const _fileTag = 'dav-file|';

  static const _videoExtensions = {
    'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'ts', 'm2ts', 'm4v', //
    'rmvb', 'rm', 'webm', 'mpg', 'mpeg', 'iso',
  };

  /// Extensions that are never playable and never a title.
  static const _junkExtensions = {
    'nfo', 'srt', 'ass', 'ssa', 'vtt', 'sub', 'idx', 'jpg', 'jpeg', 'png', //
    'webp', 'bmp', 'gif', 'txt', 'json', 'db', 'ini', 'url', 'torrent',
    'part', 'tmp',
  };

  // ---------------------------------------------------------------------------
  // MediaMount
  // ---------------------------------------------------------------------------

  @override
  Future<List<MediaItem>> library({int limit = 24}) async {
    final entries = await _list(baseUri);
    final items = <MediaItem>[];
    for (final entry in entries) {
      final item = _itemFor(entry);
      if (item == null) continue;
      items.add(item);
      if (items.length >= limit) break;
    }
    return items;
  }

  /// Case-insensitive title match over the root and one level down.
  ///
  /// Bounded on purpose: a WebDAV search means listing directories, and walking
  /// an AList share would take minutes. The first level covers "find me that
  /// series", which is what the search box is for.
  @override
  Future<List<MediaItem>> search(String keyword, {int limit = 60}) async {
    final needle = keyword.trim().toLowerCase();
    if (needle.isEmpty) return library(limit: limit);

    final root = await _list(baseUri);
    final hits = <MediaItem>[];
    final dirs = <_DavEntry>[];
    for (final entry in root) {
      final item = _itemFor(entry);
      if (item == null) continue;
      if (item.title.toLowerCase().contains(needle)) {
        hits.add(item);
      } else if (entry.isDir) {
        dirs.add(entry);
      }
      if (hits.length >= limit) return hits;
    }

    // One level in, in parallel: a share usually groups by title, but the file
    // that matches may sit inside a folder named after something else.
    final pages = await Future.wait([
      for (final dir in dirs.take(_searchDirs))
        _list(baseUri.resolve(dir.href)).catchError((Object _) => <_DavEntry>[]),
    ]);
    for (final children in pages) {
      for (final child in children) {
        final item = _itemFor(child);
        if (item == null) continue;
        if (!item.title.toLowerCase().contains(needle)) continue;
        hits.add(item);
        if (hits.length >= limit) return hits;
      }
    }
    return hits;
  }

  @override
  Future<MediaItem> detail(MediaItem item) async {
    final href = _hrefOf(item.id);
    if (href == null) return item;

    // A loose file plays as a single 正片.
    if (item.id.startsWith(_fileTag)) {
      return item.withDetail(
        playLines: [
          PlayLine(
            name: _lineName,
            episodes: [PlayEpisode(label: '正片', url: streamUrl(item.id))],
          ),
        ],
      );
    }

    final entries = await _list(baseUri.resolve(href));
    final videos = <_DavEntry>[];
    final subdirs = <_DavEntry>[];
    for (final entry in entries) {
      if (entry.isDir) {
        subdirs.add(entry);
      } else if (_isVideo(entry.name)) {
        videos.add(entry);
      }
    }
    // `Season 1` / `Disc 1` layout: one level down is still the same title.
    if (videos.isEmpty && subdirs.isNotEmpty) {
      final nested = await Future.wait([
        for (final dir in subdirs.take(_detailSubdirs))
          _list(
            baseUri.resolve(dir.href),
          ).catchError((Object _) => <_DavEntry>[]),
      ]);
      for (final children in nested) {
        videos.addAll(children.where((e) => !e.isDir && _isVideo(e.name)));
      }
    }

    if (videos.isEmpty) {
      return item.withDetail(overview: '这个目录里没有视频文件');
    }

    videos.sort((a, b) => _naturalCompare(a.name, b.name));
    final parsed = [
      for (final video in videos) _parseName(video.name),
    ];

    // Three shapes live in one folder on a share, and guessing wrong is worse
    // than asking: a single file is 正片, files numbered alike are episodes,
    // and files with different names are just films sitting in the same folder.
    final episodic = parsed.every((p) => p.episode != null);
    final sameTitle = parsed.map((p) => p.title).toSet().length == 1;
    final labels = <String>[];
    final plays = <PlayEpisode>[];
    for (var i = 0; i < videos.length; i++) {
      final String label;
      if (videos.length == 1) {
        label = '正片';
      } else if (episodic) {
        label = parsed[i].label ?? '第${i + 1}集';
      } else if (sameTitle) {
        label = '第${i + 1}集';
      } else {
        label = parsed[i].title;
      }
      labels.add(label);
      plays.add(
        PlayEpisode(
          label: label,
          url: streamUrl('$_fileTag${videos[i].href}'),
        ),
      );
    }
    return item.withDetail(
      latest: episodic && labels.length > 1 ? labels.last : null,
      episodes: labels,
      playLines: [PlayLine(name: _lineName, episodes: plays)],
    );
  }

  /// `播放列表` is the line name the detail page prints for a mount; matching
  /// Emby keeps one vocabulary across both kinds of source.
  static const _lineName = '播放列表';

  @override
  Future<ProbeReport> probe() async {
    final watch = Stopwatch()..start();
    try {
      final entries = await _list(baseUri);
      watch.stop();
      var files = 0;
      var dirs = 0;
      for (final entry in entries) {
        if (entry.isDir) {
          if (!_isNoiseDir(entry.name)) dirs++;
        } else if (_isVideo(entry.name)) {
          files++;
        }
      }
      if (files == 0 && dirs == 0) {
        return ProbeReport(
          latencyMs: watch.elapsedMilliseconds,
          movieCount: 0,
          showCount: 0,
          note: '连上了，但这个目录是空的',
        );
      }
      return ProbeReport(
        latencyMs: watch.elapsedMilliseconds,
        movieCount: files,
        showCount: dirs,
        note: null,
      );
    } on MountException catch (e) {
      watch.stop();
      return ProbeReport(
        latencyMs: watch.elapsedMilliseconds,
        error: e.message,
      );
    } on Object catch (e) {
      watch.stop();
      return ProbeReport(latencyMs: watch.elapsedMilliseconds, error: '$e');
    }
  }

  /// Only a file is playable. A directory id resolves to the folder URL, which
  /// is not a stream -- returning it would hand the player an HTML listing and
  /// produce an error with no explanation. The caller opens a directory by
  /// asking for its detail first.
  @override
  String streamUrl(String itemId) {
    if (!itemId.startsWith(_fileTag)) return '';
    final href = _hrefOf(itemId);
    if (href == null) return '';
    return baseUri.resolve(href).toString();
  }

  @override
  void close() {
    if (_ownsHttp) _http.close(force: true);
  }

  // ---------------------------------------------------------------------------
  // PROPFIND
  // ---------------------------------------------------------------------------

  static const _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:displayname/><d:resourcetype/><d:getcontentlength/>'
      '</d:prop></d:propfind>';

  /// Lists one level. Depth 1 includes the directory itself, which is filtered
  /// out by comparing hrefs.
  ///
  /// Every transport failure surfaces as [MountException]: a share that reset
  /// the connection is "连不上这个目录", not a raw `HttpException` thrown into a
  /// page that has no idea what to do with one.
  Future<List<_DavEntry>> _list(Uri uri) async {
    try {
      return await _listOnce(uri);
    } on MountException {
      rethrow;
    } on Object catch (e) {
      throw MountException('连不上这个目录（$e）');
    }
  }

  Future<List<_DavEntry>> _listOnce(Uri uri) async {
    final request = await _http.openUrl('PROPFIND', uri).timeout(timeout);
    request.headers.set(HttpHeaders.authorizationHeader, auth);
    request.headers.set('Depth', '1');
    request.headers.contentType = ContentType(
      'application',
      'xml',
      charset: 'utf-8',
    );
    request.write(_propfindBody);

    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join();
    switch (response.statusCode) {
      case 207:
      case 200:
        break;
      case 401:
        throw const MountException('账号或密码不对');
      case 403:
        throw const MountException('服务器拒绝了这个账号（403）');
      case 404:
        throw const MountException('路径不存在（404）');
      default:
        throw MountException('服务器返回 ${response.statusCode}');
    }

    final entries = _parse(body);
    // Drop the directory's own row: the server echoes it as the first entry.
    final self = _normalize(uri.path);
    final out = <_DavEntry>[];
    for (final entry in entries) {
      if (_normalize(Uri.parse(entry.href).path) == self) continue;
      out.add(entry);
    }
    return out;
  }

  /// Reads `multistatus` without pulling in an XML package: the shape is one
  /// flat list of `response` blocks, and every value needed is a leaf element.
  List<_DavEntry> _parse(String xml) {
    final out = <_DavEntry>[];
    final blocks = RegExp(
      r'<(?:[A-Za-z0-9._-]+:)?response\b[^>]*>([\s\S]*?)'
      r'</(?:[A-Za-z0-9._-]+:)?response>',
    );
    for (final match in blocks.allMatches(xml)) {
      final body = match.group(1) ?? '';
      final href = _leaf(body, 'href');
      if (href == null || href.isEmpty) continue;
      final display = _leaf(body, 'displayname');
      final isDir = RegExp(
        r'<(?:[A-Za-z0-9._-]+:)?collection\b',
      ).hasMatch(body);
      final name = (display != null && display.isNotEmpty)
          ? display
          : Uri.decodeComponent(
              href.endsWith('/') ? href.substring(0, href.length - 1) : href,
            ).split('/').where((s) => s.isNotEmpty).lastOrNull ??
              '';
      out.add(_DavEntry(href: href, name: name, isDir: isDir));
    }
    return out;
  }

  /// Text of the first `<name>` leaf anywhere inside [body], entities decoded.
  String? _leaf(String body, String name) {
    final match = RegExp(
      '<(?:[A-Za-z0-9._-]+:)?$name\\b[^>]*>([\\s\\S]*?)'
      '</(?:[A-Za-z0-9._-]+:)?$name>',
    ).firstMatch(body);
    if (match == null) return null;
    return _unescape(match.group(1) ?? '').trim();
  }

  static String _unescape(String value) => value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  // ---------------------------------------------------------------------------
  // Records
  // ---------------------------------------------------------------------------

  /// A directory or a playable file as a card, or null for a row that can never
  /// be a title (a subtitle, an image, a thumbnail folder).
  MediaItem? _itemFor(_DavEntry entry) {
    if (entry.isDir) {
      if (_isNoiseDir(entry.name)) return null;
      final parsed = _parseName(entry.name);
      return MediaItem(
        id: '$_dirTag${entry.href}',
        title: parsed.title,
        latest: parsed.label,
        year: parsed.year,
        sourceName: sourceName,
      );
    }
    if (!_isVideo(entry.name)) return null;
    final parsed = _parseName(entry.name);
    return MediaItem(
      id: '$_fileTag${entry.href}',
      title: parsed.title,
      latest: parsed.label,
      year: parsed.year,
      sourceName: sourceName,
    );
  }

  static bool _isVideo(String name) {
    final ext = _extensionOf(name);
    return ext != null && _videoExtensions.contains(ext);
  }

  /// Folders that exist to hold metadata, not titles.
  static bool _isNoiseDir(String name) {
    final lower = name.toLowerCase();
    return lower == '@eadir' ||
        lower == '#recycle' ||
        lower == '@recycle' ||
        lower == '.thumbnails' ||
        lower.startsWith('@eaDir'.toLowerCase()) ||
        lower == 'recycle' ||
        lower == 'thumbnails';
  }

  static String? _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    final ext = name.substring(dot + 1).toLowerCase();
    if (_junkExtensions.contains(ext)) return null;
    return ext;
  }

  /// Pulls a title, a year and an episode label out of a file or folder name.
  ///
  /// Handles the shapes a share actually uses: `流浪地球2.2023.2160p`, `[小组]
  /// 庆余年 S02E05 [1080p]`, `三体 第12集`. Everything it cannot recognise is
  /// left in the title rather than guessed at.
  static ({String title, int? year, int? season, int? episode, String? label})
  _parseName(String raw) {
    var name = raw;
    final dot = name.lastIndexOf('.');
    if (dot > 0) {
      final ext = name.substring(dot + 1).toLowerCase();
      if (ext.length <= 4 && RegExp(r'^[a-z0-9]+$').hasMatch(ext)) {
        final isVideoOrJunk =
            _videoExtensions.contains(ext) || _junkExtensions.contains(ext);
        if (isVideoOrJunk) name = name.substring(0, dot);
      }
    }

    int? season;
    int? episode;
    String? label;

    final se = RegExp(
      r'[Ss](\d{1,2})\s*[Ee](\d{1,3})',
    ).firstMatch(name);
    final epOnly = RegExp(r'(?<![A-Za-z])[Ee][Pp]?(\d{1,3})(?!\d)').firstMatch(name);
    final chinese = RegExp(r'第\s*(\d{1,4})\s*[集话話期]').firstMatch(name);

    if (se != null) {
      season = int.parse(se.group(1)!);
      episode = int.parse(se.group(2)!);
      label = '第$episode集';
      name = name.replaceRange(se.start, se.end, ' ');
    } else if (chinese != null) {
      episode = int.parse(chinese.group(1)!);
      label = '第$episode集';
      name = name.replaceRange(chinese.start, chinese.end, ' ');
    } else if (epOnly != null) {
      episode = int.parse(epOnly.group(1)!);
      label = '第$episode集';
      name = name.replaceRange(epOnly.start, epOnly.end, ' ');
    }

    int? year;
    final yearMatch = RegExp(r'(?<!\d)(19|20)(\d{2})(?!\d)').firstMatch(name);
    if (yearMatch != null) {
      year = int.parse('${yearMatch.group(1)}${yearMatch.group(2)}');
      name = name.replaceRange(yearMatch.start, yearMatch.end, ' ');
    }

    // Bracketed groups and bare release tags (`2160p`, `x265`, `WEB-DL`) are
    // about the file, not the title.
    name = name
        .replaceAll(RegExp(r'\[[^\]]*\]|【[^】]*】|\([^)]*\)|（[^）]*）'), ' ')
        .replaceAll(_releaseTags, ' ')
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (name.isEmpty) name = raw;
    return (title: name, year: year, season: season, episode: episode, label: label);
  }

  /// Tokens a release name carries that never belong to a title.
  static final RegExp _releaseTags = RegExp(
    r'\b(?:2160p|1080p|720p|576p|480p|4k|8k|uhd|hdrip|bluray|blu-ray|'
    r'web-?dl|webrip|hdtv|remux|x264|x265|h ?264|h ?265|hevc|avc|10bit|'
    r'aac|ac3|dts|ddp?\d(?:\.\d)?|atmos|hdr|sdr)\b',
    caseSensitive: false,
  );

  static int _naturalCompare(String a, String b) {
    final sa = _naturalChunks(a);
    final sb = _naturalChunks(b);
    for (var i = 0; i < sa.length && i < sb.length; i++) {
      final x = sa[i];
      final y = sb[i];
      final nx = int.tryParse(x);
      final ny = int.tryParse(y);
      final cmp = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
      if (cmp != 0) return cmp;
    }
    return sa.length.compareTo(sb.length);
  }

  static List<String> _naturalChunks(String value) =>
      RegExp(r'\d+|\D+').allMatches(value).map((m) => m.group(0)!).toList();

  static String? _hrefOf(String id) {
    if (id.startsWith(_dirTag)) return id.substring(_dirTag.length);
    if (id.startsWith(_fileTag)) return id.substring(_fileTag.length);
    return null;
  }

  /// `baseUrl` with a trailing slash, so `resolve('a/b')` joins instead of
  /// replacing the last segment.
  static Uri _normalize(String baseUrl) {
    final trimmed = baseUrl.trim();
    final withSlash = trimmed.endsWith('/') ? trimmed : '$trimmed/';
    return Uri.parse(withSlash);
  }

  static String _basicAuth(String username, String password) {
    final raw = '$username:$password';
    return 'Basic ${base64Encode(utf8.encode(raw))}';
  }

  /// Bounded fan-out for [search] and for `Season N` folders.
  static const _searchDirs = 12;
  static const _detailSubdirs = 4;
}

/// One row of a `PROPFIND` answer.
class _DavEntry {
  const _DavEntry({
    required this.href,
    required this.name,
    required this.isDir,
  });

  /// As the server returned it: absolute path or full URL.
  final String href;
  final String name;
  final bool isDir;
}

extension<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
