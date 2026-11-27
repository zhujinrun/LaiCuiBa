import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../source_import.dart' show appDataDirectory;

/// 一个用户自己配的字幕网站。URL 模板支持 `{query}` 占位符；不写占位符时
/// 关键词作为 `q` 查询参数附上。配置只保存在本机。
class SubtitleSite {
  const SubtitleSite({
    required this.id,
    required this.name,
    required this.urlTemplate,
  });

  final String id;
  final String name;
  final String urlTemplate;

  Uri uriFor(String query) {
    final encoded = Uri.encodeComponent(query);
    final raw = urlTemplate.contains('{query}')
        ? urlTemplate.replaceAll('{query}', encoded)
        : '$urlTemplate${urlTemplate.contains('?') ? '&' : '?'}q=$encoded';
    return Uri.parse(raw);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'urlTemplate': urlTemplate,
  };

  factory SubtitleSite.fromJson(Map<String, dynamic> json) => SubtitleSite(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    urlTemplate: json['urlTemplate'] as String? ?? '',
  );
}

class SubtitleHit {
  const SubtitleHit({
    required this.title,
    required this.url,
    this.language = '',
    this.format = 'srt',
  });

  final String title;
  final String url;
  final String language;
  final String format;
}

/// 字幕网站搜索与下载。响应认两种常见形状：顶层数组，或 `{results:[...]}` /
/// `{subtitles:[...]}` / `{data:[...]}`；字段按原版常见命名做兼容。
class SubtitleSiteService {
  SubtitleSiteService._();

  static Directory? directoryOverride;

  static Directory directory() {
    final dir = Directory(
      p.join((directoryOverride ?? appDataDirectory()).path, 'subtitles'),
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<List<SubtitleHit>> search(
    SubtitleSite site,
    String query,
  ) async {
    if (query.trim().isEmpty) return const [];
    final bytes = await _get(site.uriFor(query), maxBytes: 4 * 1024 * 1024);
    Object decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on Object {
      throw const FormatException('字幕网站返回的不是可识别的 JSON');
    }
    final list = decoded is List
        ? decoded
        : decoded is Map
            ? decoded['results'] ?? decoded['subtitles'] ?? decoded['data']
            : null;
    if (list is! List) return const [];
    final hits = <SubtitleHit>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final url = '${raw['url'] ?? raw['link'] ?? raw['download'] ?? ''}';
      if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
      hits.add(
        SubtitleHit(
          title: '${raw['title'] ?? raw['name'] ?? raw['fileName'] ?? '未命名字幕'}',
          url: url,
          language: '${raw['language'] ?? raw['lang'] ?? ''}',
          format: _formatOf('${raw['format'] ?? raw['ext'] ?? ''}', url),
        ),
      );
    }
    return hits;
  }

  static Future<File> download(SubtitleHit hit) async {
    final bytes = await _get(Uri.parse(hit.url), maxBytes: 5 * 1024 * 1024);
    final name = '${md5.convert(bytes).toString()}.${hit.format}';
    final file = File(p.join(directory().path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<List<int>> _get(Uri uri, {required int maxBytes}) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set('accept', 'application/json, text/plain, */*');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FormatException('字幕网站返回 HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) throw const FormatException('字幕文件过大');
      }
      return bytes;
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('字幕网站打不开：$error');
    } finally {
      client.close();
    }
  }

  static String _formatOf(String declared, String url) {
    final fromDeclared = declared.toLowerCase().replaceAll('.', '');
    if (fromDeclared == 'srt' ||
        fromDeclared == 'ass' ||
        fromDeclared == 'vtt') {
      return fromDeclared;
    }
    final ext = p.extension(Uri.parse(url).path).toLowerCase().replaceAll('.', '');
    return ext == 'ass' || ext == 'vtt' ? ext : 'srt';
  }
}
