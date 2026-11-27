import 'dart:convert';
import 'dart:io';

import '../models/models.dart';

/// TMDB v3 的最小真实数据源，只做首页组件区域需要的「热门片单」。
///
/// Key 来自设置里用户自己填的那一个，不随应用分发，也不进备份。没有 Key
/// 时界面明说「请先到设置配置 TMDB API Key」，不回落假片单。
class TmdbService {
  TmdbService._();

  static const baseUrl = 'https://api.themoviedb.org/3';
  static const imageBase = 'https://image.tmdb.org/t/p/w500';

  static Future<List<MediaItem>> trending(
    String apiKey, {
    String kind = 'movie',
    int page = 1,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/trending/$kind/week?api_key=${Uri.encodeComponent(apiKey)}'
      '&language=zh-CN&page=$page',
    );
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set('accept', 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 401) {
        throw const FormatException('TMDB API Key 无效');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FormatException('TMDB 推荐加载失败，HTTP ${response.statusCode}');
      }
      return parseTrending(jsonDecode(body), kind: kind);
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('TMDB 推荐加载失败：$error');
    } finally {
      client.close();
    }
  }

  /// 解析 TMDB 的 `results` 数组。抽成纯函数，测试不需要碰网络。
  static List<MediaItem> parseTrending(Object? data, {String kind = 'movie'}) {
    final results = data is Map ? data['results'] : null;
    if (results is! List) return const [];
    final items = <MediaItem>[];
    for (final raw in results) {
      if (raw is! Map) continue;
      final id = '${raw['id'] ?? ''}';
      if (id.isEmpty || id == 'null') continue;
      final title = '${raw['title'] ?? raw['name'] ?? ''}';
      if (title.isEmpty) continue;
      final poster = '${raw['poster_path'] ?? ''}';
      final date = '${raw[kind == 'tv' ? 'first_air_date' : 'release_date'] ?? ''}';
      final year = int.tryParse(date.length >= 4 ? date.substring(0, 4) : '');
      final score = raw['vote_average'];
      items.add(
        MediaItem(
          id: 'tmdb-$id',
          title: title,
          subtitle: '${raw['overview'] ?? ''}'.trim().isEmpty
              ? null
              : '${raw['overview']}',
          score: score is num ? score.toDouble() : null,
          tag: 'TMDB',
          year: year,
          image: poster.isEmpty || poster == 'null'
              ? null
              : '$imageBase$poster',
          siteKey: 'tmdb',
        ),
      );
    }
    return items;
  }
}
