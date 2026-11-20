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
    return _listFrom(json);
  }

  /// Full record for one `vod_id`. `id` is singular, matching the source.
  Future<MediaItem?> detail(String storeKey, String type, String vodId) async {
    final json = await _call(storeKey, type, 'detail', {'id': vodId});
    final list = (json['list'] as List?) ?? const [];
    if (list.isEmpty) return null;
    final raw = list.first;
    if (raw is! Map) return null;
    return _vodToItem(Map<String, dynamic>.from(raw), storeKey);
  }

  Future<Map<String, dynamic>> _call(
    String storeKey,
    String type,
    String action, [
    Map<String, dynamic>? body,
  ]) async {
    final key = spiderKey(storeKey);
    final uri = Uri.parse('http://127.0.0.1:$port/spider/$key/$type/$action');
    final request = await _client.postUrl(uri);
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );
    request.add(utf8.encode(jsonEncode(body ?? const {})));
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (text.trim().isEmpty) return const {};
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  SpiderList _listFrom(Map<String, dynamic> json) {
    final list = (json['list'] as List?) ?? const [];
    final items = <MediaItem>[];
    for (final raw in list) {
      if (raw is Map) {
        items.add(_vodToItem(Map<String, dynamic>.from(raw), null));
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
  static MediaItem _vodToItem(Map<String, dynamic> vod, String? siteKey) {
    final remarks = vod['vod_remarks'] as String? ?? '';
    final typeName = vod['type_name'] as String? ?? '';
    final actor = vod['vod_actor'] as String? ?? '';
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
      siteKey: siteKey,
    );
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
