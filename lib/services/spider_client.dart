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
  /// The site's categories, or null when the site did not answer at all.
  ///
  /// A reply without a `class` key is not an empty site: it is the host or the
  /// site refusing the call (a wrong key returns `{error}`), and the home page
  /// says "没答上来" for that instead of "没有推荐内容".
  Future<List<SpiderClass>?> home(String storeKey, String type) async =>
      (await homeFull(storeKey, type))?.classes;

  /// The whole `home` answer: categories plus the per-category filter groups
  /// the browse panel needs.
  ///
  /// `filters` is keyed by the category's `type_id` and each group looks like
  /// `{key:'class'|'area'|'year'|'by', init:'time', value:[{n:'全部', v:''}]}`.
  /// Verified against the live 豆儿猫源: group `by` ships no "全部" option, so
  /// the panel adds one rather than inventing a default the source never had.
  Future<SpiderHome?> homeFull(String storeKey, String type) async {
    final json = await _call(storeKey, type, 'home');
    if (json == null || !json.containsKey('class')) return null;
    final classes = (json['class'] as List?) ?? const [];
    return SpiderHome(
      classes: [
        for (final raw in classes)
          if (raw is Map)
            SpiderClass(
              typeId: '${raw['type_id'] ?? ''}',
              name: raw['type_name'] as String? ?? '',
            ),
      ],
      filters: parseFilters(json['filters']),
    );
  }

  /// Parses the `filters` block of a `home` answer. Public because a TVBox
  /// (Python/JS) source answers with the very same shape.
  static Map<String, List<SpiderFilterGroup>> parseFilters(Object? raw) {
    final out = <String, List<SpiderFilterGroup>>{};
    if (raw is! Map) return out;
    for (final entry in raw.entries) {
      final list = entry.value;
      if (list is! List) continue;
      final groups = <SpiderFilterGroup>[];
      for (final rawGroup in list) {
        if (rawGroup is! Map) continue;
        final options = <SpiderFilterOption>[];
        final values = rawGroup['value'];
        if (values is List) {
          for (final rawOption in values) {
            if (rawOption is! Map) continue;
            final label = '${rawOption['n'] ?? ''}'.trim();
            if (label.isEmpty) continue;
            options.add(
              SpiderFilterOption(
                label: label,
                value: '${rawOption['v'] ?? ''}'.trim(),
              ),
            );
          }
        }
        if (options.isEmpty) continue;
        groups.add(
          SpiderFilterGroup(
            key: '${rawGroup['key'] ?? ''}'.trim(),
            init: '${rawGroup['init'] ?? ''}'.trim(),
            options: options,
          ),
        );
      }
      if (groups.isNotEmpty) out['${entry.key}'] = groups;
    }
    return out;
  }

  /// Category feed for one `tid`. Can legitimately come back empty when the
  /// upstream site has not published a fresh feed for that category.
  ///
  /// The body is `{id, page}`. TVBox's `{tid, pg}` -- which is what this sent
  /// until 2026-11-22 -- is not rejected: the source answers
  /// `{list: [], page: 1, pagecount: 1, total: 72}`. A silent empty list is
  /// exactly why every rail looked dry while the original filled them, so the
  /// field names are verified against the live source rather than assumed.
  Future<SpiderList> category(
    String storeKey,
    String type, {
    String tid = '1',
    String page = '1',
    Map<String, String> filters = const {},
  }) async {
    final json = await _call(storeKey, type, 'category', {
      'id': tid,
      'page': page,
      // The source reads the browse panel's conditions from `filters`, not from
      // TVBox's `extend`. Measured on the live source: `{by:'score'}` reorders
      // the same 144 titles (first card 牢笼鬼魂 -> 阴风诡影), `{class:'喜剧'}`
      // narrows the list, while `extend` in either shape changes nothing.
      if (filters.isNotEmpty) 'filters': filters,
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

/// What `home` answers: the site's categories and, per category id, the
/// filter groups its browse page offers.
class SpiderHome {
  const SpiderHome({required this.classes, this.filters = const {}});

  final List<SpiderClass> classes;

  /// `type_id` -> groups. Empty when the site declared no filters.
  final Map<String, List<SpiderFilterGroup>> filters;

  /// The groups to show for [typeId]; empty when that category has none.
  List<SpiderFilterGroup> groupsFor(String typeId) =>
      filters[typeId] ?? const [];
}

/// One row of chips in the browse panel, e.g. 类型 / 地区 / 年份 / 排序.
class SpiderFilterGroup {
  const SpiderFilterGroup({
    required this.key,
    required this.init,
    required this.options,
  });

  /// The body key this group travels under (`class` / `area` / `year` / `by`).
  final String key;

  /// The source's own default, when it declares one.
  final String init;

  final List<SpiderFilterOption> options;
}

class SpiderFilterOption {
  const SpiderFilterOption({required this.label, required this.value});

  final String label;
  final String value;
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
