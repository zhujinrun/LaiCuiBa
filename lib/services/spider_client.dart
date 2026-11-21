import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/models.dart';

/// Client for the catvod spider HTTP interface of a loaded 猫源.
///
/// A loaded source exposes one fastify server; every site behind it is a spider
/// registered at `POST /spider/<key>/<type>/<action>` where `<key>` is the
/// bundle's `meta.key` (no `nodejs_` prefix) and `<action>` is one of
/// `init / home / category / detail / play / search`. This client turns those
/// calls into typed results and maps the vod rows onto [MediaItem].
///
/// The shapes were verified against the live 豆儿猫源 (jianpian/3) on 2026-11-20:
///   * `search {wd}`  -> `{page, pagecount, total, list:[vod...]}` (reliable)
///   * `detail {id}`  -> `{list:[vod...]}` (note: `id`, singular, not `ids`)
///   * `home {}`      -> `{class:[{type_id,type_name}], filters:{}}` (categories
///     only; the per-category feed comes from `category`, which can be empty).
class SpiderClient {
  SpiderClient(this.port, {HttpClient? client})
    : _client = client ?? HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);

  final int port;
  final HttpClient _client;

  /// Strips the host's `nodejs_` prefix off a store site key. The store keeps
  /// `nodejs_jianpian` (matching the original's `homeSite`), but the spider
  /// registry keys on the bare `jianpian`.
  static String spiderKey(String storeKey) => storeKey.startsWith('nodejs_')
      ? storeKey.substring('nodejs_'.length)
      : storeKey;

  /// A category row from `home` (`class`).
  Future<List<SpiderClass>> home(String storeKey, String type) async {
    final json = await _call(storeKey, type, 'home');
    if (json == null) return const [];
    final classes = (json['class'] as List?) ?? const [];
    return [
      for (final raw in classes)
        if (raw is Map)
          SpiderClass(
            typeId: '${raw['type_id'] ?? ''}',
            name: raw['type_name'] as String? ?? '',
          ),
    ];
  }

  /// Category feed for one `tid`. Can legitimately come back empty when the
  /// upstream site has not published a fresh feed for that category.
  Future<SpiderList> category(
    String storeKey,
    String type, {
    String tid = '1',
    String page = '1',
  }) async {
    final json = await _call(storeKey, type, 'category', {
      'tid': tid,
      'pg': page,
    });
    if (json == null) return _emptyList;
    return _listFrom(json);
  }

  /// Keyword search. `strict` mirrors the original's 严格 toggle (exact title).
  Future<SpiderList> search(
    String storeKey,
    String type,
    String keyword, {
    bool strict = false,
  }) async {
    final json = await _call(storeKey, type, 'search', {
      'wd': keyword,
      if (strict) 'quick': true,
    });
    if (json == null) return _emptyList;
    return _listFrom(json);
  }

  /// Full record for one `vod_id`. `id` is singular, matching the source.
  Future<MediaItem?> detail(String storeKey, String type, String vodId) async {
    final json = await _call(storeKey, type, 'detail', {'id': vodId});
    if (json == null) return null;
    final list = (json['list'] as List?) ?? const [];
    if (list.isEmpty) return null;
    final raw = list.first;
    if (raw is! Map) return null;
    return vodToItem(Map<String, dynamic>.from(raw), storeKey);
  }

  /// Resolves the play URL for one episode.
  ///
  /// The catvod `play` action takes `{id, flag, nid}` where `flag` is the line
  /// name (线路) and `nid` the episode index, and answers either a single URL
  /// (`{url}` / `{parse:0, url}`) or a list (`{list:[{url}]}`). This returns
  /// the first usable URL, or null when the source has nothing to play.
  Future<String?> play(
    String storeKey,
    String type,
    String vodId, {
    String? flag,
    int? nid,
  }) async {
    final json = await _call(storeKey, type, 'play', {
      'id': vodId,
      if (flag != null && flag.isNotEmpty) 'flag': flag,
      if (nid != null) 'nid': nid,
    });
    if (json == null) return null;
    // list form: {list:[{url}]}
    final list = json['list'] as List?;
    if (list != null && list.isNotEmpty && list.first is Map) {
      final first = list.first as Map;
      final url = first['url'];
      if (url is String && url.trim().isNotEmpty) return url.trim();
    }
    // single form: {url}
    final url = json['url'];
    if (url is String && url.trim().isNotEmpty) return url.trim();
    return null;
  }

  /// Posts one spider action and returns its JSON body, or null when the source
  /// cannot be reached (host unloaded, worker crashed, port refused) or answers
  /// something that is not a JSON object.
  ///
  /// It deliberately swallows transport failures: a source that has just been
  /// unloaded must read as "no data", not as a `SocketException` thrown into the
  /// UI. Callers translate null into their own empty result.
  Future<Map<String, dynamic>?> _call(
    String storeKey,
    String type,
    String action, [
    Map<String, dynamic>? body,
  ]) async {
    final key = spiderKey(storeKey);
    final uri = Uri.parse('http://127.0.0.1:$port/spider/$key/$type/$action');
    try {
      final request = await _client.postUrl(uri);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.add(utf8.encode(jsonEncode(body ?? const {})));
      // A site whose upstream is slow must not stall the whole fan-out: bound
      // the full round-trip so a single dead backend cannot hold every other
      // site up.
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final text = await utf8.decodeStream(response).timeout(
        const Duration(seconds: 12),
      );
      if (text.trim().isEmpty) return const {};
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on Object {
      return null;
    }
  }

  static const _emptyList = SpiderList(
    items: [],
    page: 1,
    pageCount: 1,
    total: 0,
  );

  SpiderList _listFrom(Map<String, dynamic> json) {
    final list = (json['list'] as List?) ?? const [];
    final items = <MediaItem>[];
    for (final raw in list) {
      if (raw is Map) {
        items.add(vodToItem(Map<String, dynamic>.from(raw), null));
      }
    }
    return SpiderList(
      items: items,
      page: int.tryParse('${json['page'] ?? 1}') ?? 1,
      pageCount: int.tryParse('${json['pagecount'] ?? 1}') ?? 1,
      total: int.tryParse('${json['total'] ?? items.length}') ?? items.length,
    );
  }

  /// Maps one catvod `vod` row onto [MediaItem]. `siteKey` is the store's
  /// prefixed key; pass null from a batch where the caller tags them itself.
  ///
  /// Public because a TVBox (Python) source answers with the very same `vod`
  /// object — catvod inherited the field names — so `TvBoxSource` reuses this
  /// rather than keeping a second, drifting copy of the mapping.
  static MediaItem vodToItem(Map<String, dynamic> vod, String? siteKey) {
    final remarks = vod['vod_remarks'] as String? ?? '';
    final typeName = vod['type_name'] as String? ?? '';
    final actor = vod['vod_actor'] as String? ?? '';
    final lines = parsePlayLines(vod['vod_play_from'], vod['vod_play_url']);
    // The episode labels are the same across every line (a line only changes
    // the URL), so the first non-empty line supplies the canonical episode list.
    final firstLineEpisodes = lines.isEmpty
        ? const <String>[]
        : lines
              .firstWhere(
                (l) => l.episodes.isNotEmpty,
                orElse: () => const PlayLine(name: ''),
              )
              .episodes
              .map((e) => e.label)
              .toList(growable: false);
    return MediaItem(
      id: '${vod['vod_id'] ?? ''}',
      title: vod['vod_name'] as String? ?? '',
      image: (vod['vod_pic'] as String?)?.trim().isNotEmpty == true
          ? vod['vod_pic'] as String
          : null,
      tag: remarks.isEmpty ? null : remarks,
      latest: remarks.isEmpty ? null : remarks,
      year: int.tryParse('${vod['vod_year'] ?? ''}'),
      overview: (vod['vod_content'] as String?)?.trim().isNotEmpty == true
          ? vod['vod_content'] as String
          : null,
      area: (vod['vod_area'] as String?)?.trim().isNotEmpty == true
          ? vod['vod_area'] as String
          : null,
      categories: typeName.isEmpty
          ? const []
          : typeName.split('/').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      actors: actor.isEmpty
          ? const []
          : actor.split('/').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      episodes: firstLineEpisodes,
      playLines: lines,
      siteKey: siteKey,
    );
  }

  /// Parses the catvod `vod_play_from` / `vod_play_url` pair into [PlayLine]s.
  ///
  /// `vod_play_from` lists line names separated by `$$$`; `vod_play_url` holds
  /// the parallel episode block per line, also `$$$`-separated. Inside a block
  /// episodes are `#`-separated and each episode is `label$url` (split on the
  /// first `$` so a URL that itself contains `$` survives).
  static List<PlayLine> parsePlayLines(
    Object? playFrom,
    Object? playUrl,
  ) {
    final from = playFrom is String ? playFrom.trim() : '';
    final url = playUrl is String ? playUrl.trim() : '';
    if (from.isEmpty && url.isEmpty) return const [];

    final names = from.split(r'$$$');
    final blocks = url.split(r'$$$');

    final lines = <PlayLine>[];
    final count = names.length > blocks.length ? names.length : blocks.length;
    for (var i = 0; i < count; i++) {
      final name = i < names.length ? names[i].trim() : '';
      final block = i < blocks.length ? blocks[i] : '';
      final episodes = <PlayEpisode>[];
      if (block.isNotEmpty) {
        for (final part in block.split('#')) {
          final sep = part.indexOf(r'$');
          final label = sep < 0 ? part.trim() : part.substring(0, sep).trim();
          final epUrl = sep < 0 ? '' : part.substring(sep + 1).trim();
          if (label.isEmpty && epUrl.isEmpty) continue;
          episodes.add(PlayEpisode(label: label, url: epUrl));
        }
      }
      if (name.isEmpty && episodes.isEmpty) continue;
      lines.add(PlayLine(name: name, episodes: episodes));
    }
    return lines;
  }
}

class SpiderClass {
  const SpiderClass({required this.typeId, required this.name});

  final String typeId;
  final String name;
}

class SpiderList {
  const SpiderList({
    required this.items,
    required this.page,
    required this.pageCount,
    required this.total,
  });

  final List<MediaItem> items;
  final int page;
  final int pageCount;
  final int total;
}
