import 'dart:async';
import 'dart:convert';

import '../source_host.dart';
import 'widget_models.dart';

/// 一只组件从 WidgetMetadata 读出的模块（Dart 侧）。
class WidgetModuleMeta {
  const WidgetModuleMeta({
    required this.id,
    required this.title,
    required this.functionName,
    required this.type,
    this.params = const [],
  });

  final String id;
  final String title;
  final String functionName;
  final String type;
  final List<Map<String, dynamic>> params;

  factory WidgetModuleMeta.fromJson(Map<String, dynamic> json) =>
      WidgetModuleMeta(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        functionName: '${json['functionName'] ?? ''}',
        type: '${json['type'] ?? 'media_list'}',
        params: [
          for (final raw in (json['params'] as List?) ?? const [])
            if (raw is Map) Map<String, dynamic>.from(raw),
        ],
      );
}

class WidgetMeta {
  const WidgetMeta({
    required this.id,
    required this.title,
    this.description = '',
    this.version = '',
    this.author = '',
    this.site = '',
    this.icon = '',
    this.modules = const [],
  });

  final String id;
  final String title;
  final String description;
  final String version;
  final String author;
  final String site;
  final String icon;
  final List<WidgetModuleMeta> modules;

  factory WidgetMeta.fromJson(Map<String, dynamic> json) => WidgetMeta(
    id: '${json['id'] ?? ''}',
    title: '${json['title'] ?? ''}',
    description: '${json['description'] ?? ''}',
    version: '${json['version'] ?? ''}',
    author: '${json['author'] ?? ''}',
    site: '${json['site'] ?? ''}',
    icon: '${json['icon'] ?? json['iconUrl'] ?? ''}',
    modules: [
      for (final raw in (json['modules'] as List?) ?? const [])
        if (raw is Map)
          WidgetModuleMeta.fromJson(Map<String, dynamic>.from(raw)),
    ],
  );
}

/// 数据源函数的一次回答。组件自己的 console 也带回来，设置页能原样展示。
class WidgetLoadResult {
  const WidgetLoadResult({this.items = const [], this.logs = const []});

  final List<Map<String, dynamic>> items;
  final List<String> logs;
}

/// loadDetail(link) 的一次回答。字段按 CapyPlayer 文档的优先级归一。
class WidgetDetail {
  const WidgetDetail({
    this.title = '',
    this.mediaType = '',
    this.lines = const [],
    this.episodes = const [],
    this.tags = const [],
    this.cast = const [],
  });

  final String title;
  final String mediaType;
  final List<WidgetLine> lines;
  final List<WidgetEpisode> episodes;
  final List<String> tags;
  final List<String> cast;
}

class WidgetLine {
  const WidgetLine({required this.name, required this.url});

  final String name;
  final String url;
}

class WidgetEpisode {
  const WidgetEpisode({required this.label, required this.url});

  final String label;
  final String url;
}

WidgetLine _widgetLine(Object? raw) {
  final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  return WidgetLine(
    name: '${map['name'] ?? '线路'}',
    url: '${map['url'] ?? ''}',
  );
}

WidgetEpisode _widgetEpisode(Object? raw) {
  final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  return WidgetEpisode(
    label: '${map['label'] ?? ''}',
    url: '${map['url'] ?? ''}',
  );
}

WidgetDetail _detailOf(Map<String, dynamic> json) => WidgetDetail(
  title: '${json['title'] ?? ''}',
  mediaType: '${json['mediaType'] ?? ''}',
  lines: [
    for (final raw in (json['lines'] as List?) ?? const []) _widgetLine(raw),
  ],
  episodes: [
    for (final season in (json['seasons'] as List?) ?? const [])
      if (season is Map)
        for (final raw in (season['episodes'] as List?) ?? const [])
          _widgetEpisode(raw),
    for (final raw in (json['episodes'] as List?) ?? const []) _widgetEpisode(raw),
  ],
  tags: [for (final raw in (json['tags'] as List?) ?? const []) '$raw'],
  cast: [for (final raw in (json['cast'] as List?) ?? const []) '$raw'],
);

/// 组件宿主客户端。复用 TVBox 脚本宿主的 line-JSON 总线，所以超时、进程
/// 生命周期与日志策略跟其他运行时一致。
abstract class WidgetRuntimeApi {
  Future<WidgetMeta> meta(String scriptPath);
  Future<WidgetLoadResult> load(
    String scriptPath,
    String functionName,
    Map<String, dynamic> params,
  );
  Future<void> applyProxy(WidgetProxy proxy);
  Future<WidgetDetail?> detail(String scriptPath, String link);
  String get recentLog;
  Future<void> dispose();
}

class WidgetRuntime implements WidgetRuntimeApi {
  WidgetRuntime({
    required String nodePath,
    required String hostScript,
    this.callTimeout = const Duration(seconds: 35),
  }) : _host = SourceHost(
          executable: nodePath,
          script: hostScript,
          label: '组件',
          callTimeout: const Duration(seconds: 35),
        );

  final SourceHost _host;
  final Duration callTimeout;
  bool _started = false;
  String? _proxyUrl;

  Future<void> _ensure() async {
    if (_started) return;
    await _host.start();
    _started = true;
  }

  @override
  Future<WidgetMeta> meta(String scriptPath) async {
    await _ensure();
    final raw = await _host.call(
      key: '',
      path: scriptPath,
      method: 'meta',
      args: [scriptPath],
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('组件元数据不是对象');
    return WidgetMeta.fromJson(Map<String, dynamic>.from(decoded));
  }

  @override
  Future<WidgetLoadResult> load(
    String scriptPath,
    String functionName,
    Map<String, dynamic> params,
  ) async {
    await _ensure();
    await _syncProxy();
    final raw = await _host.call(
      key: '',
      path: scriptPath,
      method: 'data',
      args: [scriptPath, functionName, params],
      ext: '${callTimeout.inSeconds}',
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('组件没有给出片单');
    final items = <Map<String, dynamic>>[];
    for (final item in (decoded['items'] as List?) ?? const []) {
      if (item is Map) items.add(Map<String, dynamic>.from(item));
    }
    return WidgetLoadResult(
      items: items,
      logs: [
        for (final line in (decoded['logs'] as List?) ?? const []) '$line',
      ],
    );
  }

  @override
  Future<void> applyProxy(WidgetProxy proxy) async {
    final url = proxy.enabled ? proxy.url.trim() : '';
    if (url == _proxyUrl) return;
    _proxyUrl = url;
    if (!_started) return; // 启动时 _syncProxy 会把配置送过去
    await _host.call(
      key: '',
      path: '',
      method: 'proxy',
      args: [url],
    );
  }

  Future<void> _syncProxy() async {
    if (_proxyUrl == null) return;
    await _host.call(
      key: '',
      path: '',
      method: 'proxy',
      args: [_proxyUrl],
    );
  }

  @override
  Future<WidgetDetail?> detail(String scriptPath, String link) async {
    await _ensure();
    final raw = await _host.call(
      key: '',
      path: scriptPath,
      method: 'detail',
      args: [scriptPath, link],
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final detail = decoded['detail'];
    if (detail is! Map) return null;
    return _detailOf(Map<String, dynamic>.from(detail));
  }

  @override
  String get recentLog => _host.recentLog;

  @override
  Future<void> dispose() => _host.stop();
}
