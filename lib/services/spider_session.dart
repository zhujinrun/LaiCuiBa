import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'cat_bundle.dart';
import 'cat_host.dart';
import 'spider_client.dart';

/// One loaded 猫源: the Node host plus the bundle it runs.
///
/// This is the single seam between the app and the catvod runtime. It owns the
/// whole lifecycle -- resolve the bundle (downloading it on first use), start
/// `node.exe` with the rewritten `cat_host.js`, load the source, then answer
/// `search` / `detail` / `home` / `category`. Every method is inert: failures
/// surface as a result the caller can show, never an exception.
///
/// Nothing is started until [ensureLoaded] is called, so a source that is never
/// used costs nothing.
class SpiderSession {
  SpiderSession({
    required this.nodePath,
    required this.hostScript,
    required this.bundleRoot,
    this.messagePort = 0,
    SpiderClient Function(int port)? clientFactory,
  }) : _clientFactory = clientFactory ?? ((port) => SpiderClient(port));

  /// Absolute path to the embedded `node.exe`.
  final String nodePath;

  /// Absolute path to the rewritten `cat_host.js`.
  final String hostScript;

  /// Directory bundles are cached into (`<appdata>/LaiCuiBa/LaiCuiBa/cat`).
  final Directory bundleRoot;

  /// Port `messageToDart` events forward to (0 = none, as on desktop).
  final int messagePort;

  /// Builds the spider client for a loaded source. Injectable so tests can
  /// point the session at a fake HTTP server without booting node.exe.
  final SpiderClient Function(int port) _clientFactory;

  CatHost? _host;
  SpiderClient? _client;

  /// The source id currently loaded (matches the host's `sources` key).
  String? _loadedId;

  /// The port the loaded source's fastify server answers on.
  int? _sourcePort;

  bool get isLoaded => _sourcePort != null;

  /// The last failure message from [ensureLoaded], kept for the UI to show.
  String? lastError;

  /// Resolves the bundle and boots the host for [source], returning whether the
  /// source is now ready to query. A cached bundle keeps working when the
  /// network is down; a first download that fails leaves [lastError] set.
  Future<bool> ensureLoaded({
    required String id,
    required String md5Url,
  }) async {
    // Already running this exact source: nothing to do.
    if (_loadedId == id && _sourcePort != null) return true;

    final bundle = CatBundle(rootDir: bundleRoot);
    final resolved = await bundle.ensure(md5Url);
    if (!resolved.ok) {
      lastError = resolved.error;
      return false;
    }

    try {
      if (_host == null) {
        _host = CatHost(
          nodePath: nodePath,
          hostScript: hostScript,
          messagePort: messagePort,
        );
        await _host!.start();
      }
      final port = await _host!.loadSource(id, resolved.dir);
      _loadedId = id;
      _sourcePort = port;
      _client = _clientFactory(port);
      lastError = null;
      return true;
    } on Object catch (e) {
      lastError = '$e';
      return false;
    }
  }

  /// Marks the session as already loaded against [port], skipping the host and
  /// the bundle entirely. Exposed for tests that drive the client directly.
  @visibleForTesting
  void debugAttach(String id, int port) {
    _loadedId = id;
    _sourcePort = port;
    _client = _clientFactory(port);
    lastError = null;
  }

  /// Keyword search, fanned out to every enabled site behind [source].
  ///
  /// This is the aggregated form: it awaits every site and returns one
  /// [SpiderSearch]. Prefer [searchStream] for the UI so results appear
  /// site-by-site as each one responds.
  Future<SpiderSearch> search({
    required String sourceId,
    required String md5Url,
    required List<SiteInfo> sites,
    required String keyword,
    bool strict = false,
  }) async {
    if (!await ensureLoaded(id: sourceId, md5Url: md5Url)) {
      return SpiderSearch.failure(lastError ?? '源未就绪');
    }
    final groups = <SpiderSearchSite>[];
    await for (final group in searchStream(
      sourceId: sourceId,
      md5Url: md5Url,
      sites: sites,
      keyword: keyword,
      strict: strict,
    )) {
      groups.add(group);
    }
    return SpiderSearch(groups: groups);
  }

  /// Streams search results one site at a time, in completion order, so the UI
  /// can render each site's hits as soon as it responds instead of waiting for
  /// the slowest of ~59 sites. Sites that fail or return nothing are skipped.
  Stream<SpiderSearchSite> searchStream({
    required String sourceId,
    required String md5Url,
    required List<SiteInfo> sites,
    required String keyword,
    bool strict = false,
  }) async* {
    if (!await ensureLoaded(id: sourceId, md5Url: md5Url)) {
      // Report the failure through the aggregated path; a stream with no
      // events is indistinguishable from "no results" to the caller.
      lastError ??= '源未就绪';
      return;
    }
    final client = _client!;
    if (sites.isEmpty) return;
    // Fan out in parallel and push each site's hits into a controller as they
    // finish, so the stream emits in completion order and a slow site never
    // blocks the fast ones from appearing.
    final controller = StreamController<SpiderSearchSite>();
    var done = 0;
    final total = sites.length;
    for (final site in sites) {
      () async {
        SpiderList? list;
        try {
          list = await client.search(site.key, site.type, keyword,
              strict: strict);
        } on Object {
          // A dead site must not sink the whole query; it contributes nothing.
          list = null;
        }
        if (list != null && list.items.isNotEmpty) {
          controller.add(
            SpiderSearchSite(
              site: site.name,
              items: [
                for (final item in list.items) item.withSiteKey(site.key),
              ],
            ),
          );
        }
        done++;
        if (done == total) {
          controller.close();
        }
      }();
    }
    yield* controller.stream;
  }

  /// Full record for one `vod_id`, fetching the site's detail payload.
  Future<MediaItem?> detail({
    required String sourceId,
    required String md5Url,
    required SiteInfo site,
    required String vodId,
  }) async {
    if (!await ensureLoaded(id: sourceId, md5Url: md5Url)) return null;
    final item = await _client!.detail(site.key, site.type, vodId);
    return item?.withSiteKey(site.key);
  }

  /// Resolves the play URL for one episode of [vodId]. Returns null when the
  /// source cannot produce a URL (dead line, missing episode, runtime down).
  Future<String?> play({
    required String sourceId,
    required String md5Url,
    required SiteInfo site,
    required String vodId,
    String? flag,
    int? nid,
  }) async {
    if (!await ensureLoaded(id: sourceId, md5Url: md5Url)) return null;
    return _client!.play(site.key, site.type, vodId, flag: flag, nid: nid);
  }

  /// Home categories for the home site, e.g. 电影 / 电视剧 / 动漫 / 综艺.
  Future<List<SpiderClass>> home({
    required String sourceId,
    required String md5Url,
    required SiteInfo site,
  }) async {
    if (!await ensureLoaded(id: sourceId, md5Url: md5Url)) return const [];
    return _client!.home(site.key, site.type);
  }

  /// Category feed for one `tid`. May come back empty when the upstream site
  /// has no fresh feed for that category.
  Future<SpiderList> category({
    required String sourceId,
    required String md5Url,
    required SiteInfo site,
    required String tid,
    String page = '1',
  }) async {
    if (!await ensureLoaded(id: sourceId, md5Url: md5Url)) {
      return const SpiderList(items: [], page: 1, pageCount: 1, total: 0);
    }
    return _client!.category(site.key, site.type, tid: tid, page: page);
  }

  /// Unloads the source and shuts the host down, freeing node.exe.
  Future<void> close() async {
    final host = _host;
    if (host != null) {
      try {
        await host.stop();
      } on Object {
        // Best effort on shutdown.
      }
    }
    _host = null;
    _client = null;
    _loadedId = null;
    _sourcePort = null;
  }
}

/// A site's search results, tagged with the site they came from.
class SpiderSearchSite {
  const SpiderSearchSite({required this.site, required this.items});

  final String site;
  final List<MediaItem> items;
}

/// Search results grouped by site, matching the original's 结果按平台分组.
class SpiderSearch {
  const SpiderSearch({required this.groups, this.error});

  const SpiderSearch.failure(String message)
    : groups = const [],
      error = message;

  final List<SpiderSearchSite> groups;
  final String? error;

  bool get ok => error == null;
  int get total => groups.fold(0, (sum, g) => sum + g.items.length);
  bool get isEmpty => groups.isEmpty;
}
