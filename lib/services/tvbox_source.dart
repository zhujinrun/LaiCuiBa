import 'dart:convert';

import '../models/models.dart';
import 'source_host.dart';
import 'source_probe.dart';
import 'spider_client.dart';

/// One TVBox **script** source, spoken to through [SourceHost].
///
/// The same class drives a Python `main.py` and a TVBox-style `main.js`: both
/// runtimes answer the same protocol and both ecosystems use catvod's field
/// names, so there is one mapping instead of two drifting apart.
///
/// A TVBox `json` source is just an address pointing at a `main.py`; the module
/// exposes `homeContent / categoryContent / detailContent / searchContent /
/// playerContent` and answers with catvod-shaped dictionaries (the two
/// ecosystems share their field names — `vod_play_from`, `vod_play_url`, …),
/// so [SpiderClient.vodToItem] does the row mapping here too instead of a
/// second implementation drifting apart.
///
/// The host hands back the source's raw body as a string; this class is what
/// turns that into models, which keeps [SourceHost] free of model knowledge and
/// makes the JSON contract testable on its own.
class TvBoxSource {
  TvBoxSource({
    required this.host,
    required this.key,
    required this.path,
    this.ext = '',
    this.siteKey,
  });

  final SourceHost host;

  /// Stable id for this source; the host keys its loaded instances on it, so
  /// changing it means `init()` runs again.
  final String key;

  /// Absolute path to the source file (`.py` or `.js`).
  final String path;

  /// The `extend` string TVBox passes to `init`.
  final String ext;

  /// The site these rows belong to, when the source came out of a config with
  /// several of them. Every [MediaItem] this class produces is tagged with it,
  /// because detail and play need to come back to the same site's api.
  final String? siteKey;

  /// `home` → categories. A TVBox source may also declare `filters`; the
  /// browse panel shows them when it does, and just the categories when not.
  Future<List<SpiderClass>> home() async =>
      (await homeFull())?.classes ?? const [];

  Future<SpiderHome?> homeFull() async {
    final json = await _map('home', [true]);
    if (json == null) return null;
    final classes = (json['class'] as List?) ?? const [];
    return SpiderHome(
      classes: [
        for (final raw in classes)
          if (raw is Map)
            SpiderClass(
              typeId: '${raw['type_id'] ?? ''}',
              name: '${raw['type_name'] ?? ''}',
            ),
      ].where((c) => c.name.isNotEmpty).toList(growable: false),
      filters: SpiderClient.parseFilters(json['filters']),
    );
  }

  Future<SpiderList> category(
    String tid, {
    String page = '1',
    bool filter = true,
    Map<String, dynamic> extend = const {},
  }) => _list('category', [tid, page, filter, extend]);

  Future<SpiderList> search(
    String keyword, {
    bool quick = false,
    String page = '1',
  }) => _list('search', [keyword, quick, page]);

  /// The full record for [item], with play lines. Returns null when the source
  /// has nothing for that id (a removed title, a dead site).
  Future<MediaItem?> detail(MediaItem item) async {
    final json = await _map('detail', [item.id]);
    final list = (json?['list'] as List?) ?? const [];
    for (final raw in list) {
      if (raw is! Map) continue;
      final full = SpiderClient.vodToItem(
        Map<String, dynamic>.from(raw),
        item.siteKey ?? siteKey,
      );
      // Play lines are the point of this call; a body without them means the
      // source knows the title but cannot play it, which is worth surfacing as
      // "no result" rather than an empty player.
      if (full.playLines.isEmpty) continue;
      return full.withSiteKey(item.siteKey ?? siteKey);
    }
    return null;
  }

  /// `playerContent` → a playable URL plus the headers it asked for, or null
  /// when the source wants a browser parser instead (`parse: 1`, i.e. a vip/jx
  /// URL we cannot resolve).
  ///
  /// Most TVBox sources answer `parse: 0` with a playable `url`; anything else
  /// needs a jx parser the app does not have yet, so it says so by returning
  /// null instead of handing the player an unusable address. One call answers
  /// both questions -- asking twice per play would run the source's own
  /// resolution twice, and some of those cost a network round-trip.
  Future<TvBoxPlay?> playTarget({
    required String flag,
    required String id,
    List<String> vipFlags = const [],
  }) async {
    final json = await _map('player', [flag, id, vipFlags]);
    if (json == null) return null;
    final parse = json['parse'];
    final parseFlag = parse is num ? parse.toInt() : int.tryParse('$parse') ?? 0;
    final url = '${json['url'] ?? ''}'.trim();
    if (url.isEmpty || parseFlag != 0) return null;
    return TvBoxPlay(url: url, headers: _headersOf(json['header']));
  }

  /// The URL alone, for callers that do not need the headers.
  Future<String?> play({
    required String flag,
    required String id,
    List<String> vipFlags = const [],
  }) async {
    final target = await playTarget(flag: flag, id: id, vipFlags: vipFlags);
    return target?.url;
  }

  /// Request headers the source attached to the play URL (`header`).
  Future<Map<String, String>> playHeaders({
    required String flag,
    required String id,
    List<String> vipFlags = const [],
  }) async {
    final target = await playTarget(flag: flag, id: id, vipFlags: vipFlags);
    return target?.headers ?? const {};
  }

  static Map<String, String> _headersOf(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries) '${entry.key}': '${entry.value}',
    };
  }

  /// Boots the source and reads enough of it to answer 检测: how many
  /// categories it declares and how many titles its first one holds.
  ///
  /// Same shape as [SourceProbe]'s answer for a 猫源 -- a first-screen count, not
  /// a library total -- so the card reads the same whichever runtime served it.
  Future<ProbeReport> probe({int siteCount = 0}) async {
    final watch = Stopwatch()..start();
    try {
      final classes = await home();
      var count = 0;
      if (classes.isNotEmpty) {
        final page = await category(classes.first.typeId);
        count = page.items.map((item) => item.id).toSet().length;
      }
      return ProbeReport(
        latencyMs: watch.elapsedMilliseconds,
        movieCount: count,
        showCount: classes.length,
        siteCount: siteCount,
        note: classes.isEmpty ? '源没有返回分类' : null,
      );
    } on Object catch (e) {
      return ProbeReport.failure('$e', latencyMs: watch.elapsedMilliseconds);
    }
  }

  Future<SpiderList> _list(String method, List<Object?> args) async {
    final json = await _map(method, args);
    final raw = (json?['list'] as List?) ?? const [];
    final items = <MediaItem>[];
    for (final row in raw) {
      if (row is! Map) continue;
      items.add(
        SpiderClient.vodToItem(Map<String, dynamic>.from(row), siteKey),
      );
    }
    return SpiderList(
      items: items,
      page: int.tryParse('${json?['page'] ?? 1}') ?? 1,
      pageCount: int.tryParse('${json?['pagecount'] ?? 1}') ?? 1,
      total: int.tryParse('${json?['total'] ?? items.length}') ?? items.length,
    );
  }

  Future<Map<String, dynamic>?> _map(
    String method,
    List<Object?> args,
  ) async {
    final body = await host.call(
      key: key,
      path: path,
      method: method,
      ext: ext,
      args: args,
    );
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      // A source that answers HTML (a login wall, an error page) is broken, not
      // crashing: callers treat null as "no data" and stay honest about it.
      return null;
    }
  }
}

/// One `playerContent` answer: where to play from, and what to send with it.
class TvBoxPlay {
  const TvBoxPlay({required this.url, this.headers = const {}});

  final String url;
  final Map<String, String> headers;
}
