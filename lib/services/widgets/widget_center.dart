import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../source_import.dart' show appDataDirectory;
import '../store.dart';
import 'widget_models.dart';
import 'widget_runtime.dart';

/// 自定义页面与组件仓库的管理中心，对应原版 `widget_center.dart`。
///
/// 页面表、仓库表、组件元数据与本机代理配置都挂在 [AppSettings] 上（原始
/// JSON），所以备份会把页面和组件一起带走；代理按原版说明只保存在本机、
/// 不随备份同步（`WidgetProxy` 存在设置里但实际不会被 exportBundle 写入）。
class WidgetCenter {
  WidgetCenter._();

  static Directory directory() {
    final dir = Directory(
      p.join(appDataDirectory().path, 'widgets'),
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  // -------------------------------------------------------------------------
  // 自定义页面
  // -------------------------------------------------------------------------

  static List<CustomPage> pages(AppStore store) => [
    for (final raw in store.settings.customPages)
      if ((raw['id'] as String?)?.isNotEmpty ?? false)
        CustomPage.fromJson(raw),
  ];

  static CustomPage? page(AppStore store, String id) {
    for (final page in pages(store)) {
      if (page.id == id) return page;
    }
    return null;
  }

  static CustomPage? homePage(AppStore store) {
    final id = store.settings.homePageId;
    return id.isEmpty ? null : page(store, id);
  }

  static Future<void> savePage(AppStore store, CustomPage page) async {
    final updated = pages(store);
    final index = updated.indexWhere((candidate) => candidate.id == page.id);
    if (index >= 0) {
      updated[index] = page;
    } else {
      updated.add(page);
    }
    await _write(store, pages: updated);
  }

  static Future<void> deletePage(AppStore store, String id) async {
    final updated = pages(store)..removeWhere((page) => page.id == id);
    final home = store.settings.homePageId == id ? '' : store.settings.homePageId;
    await _write(store, pages: updated, homePageId: home);
  }

  /// 空 id 表示回到资源自己的首页。
  static Future<void> setHomePage(AppStore store, String? id) async {
    final pageId = id == null || id.isEmpty ? '' : id;
    if (pageId.isNotEmpty && page(store, pageId) == null) return;
    await _write(store, homePageId: pageId);
  }

  // -------------------------------------------------------------------------
  // 组件仓库
  // -------------------------------------------------------------------------

  static List<WidgetRepo> repos(AppStore store) => [
    for (final raw in store.settings.widgetRepos)
      if ((raw['id'] as String?)?.isNotEmpty ?? false)
        WidgetRepo.fromJson(raw),
  ];

  static List<WidgetInfo> widgets(AppStore store) => [
    for (final raw in store.settings.widgetItems)
      if ((raw['id'] as String?)?.isNotEmpty ?? false)
        WidgetInfo.fromJson(raw),
  ];

  static WidgetInfo? widget(AppStore store, String id) {
    for (final widget in widgets(store)) {
      if (widget.id == id) return widget;
    }
    return null;
  }

  static WidgetProxy proxy(AppStore store) =>
      WidgetProxy.fromJson(store.settings.widgetProxy);

  static List<String> recentLogs(AppStore store) {
    final runtime = store.widgets;
    if (runtime == null) return const [];
    return runtime.recentLog
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
  }

  /// 导入一个脚本地址、JSON 仓库索引或本地文件。
  ///
  /// 索引里的每一项都单独导入，返回第一个仓库；任何一个脚本不是组件时整批
  /// 失败，不把半套仓库留在设置里。
  static Future<WidgetRepo?> importAddress(
    AppStore store,
    String address, {
    String? name,
  }) async {
    final input = address.trim();
    if (input.isEmpty) throw const FormatException('请输入组件地址');
    if (store.widgets == null) {
      throw const FormatException('组件运行环境没有启动起来');
    }

    final isFile = !input.contains('://') && File(input).existsSync();
    if (isFile && p.extension(input).toLowerCase() == '.json') {
      final data = jsonDecode(await File(input).readAsString());
      return _importIndex(store, data, name: name);
    }

    final bytes = isFile
        ? await File(input).readAsBytes()
        : await _fetch(input);
    if (!isFile && _looksLikeJson(bytes)) {
      final data = jsonDecode(utf8.decode(bytes));
      return _importIndex(store, data, name: name);
    }
    if (bytes.length > 8 * 1024 * 1024) {
      throw const FormatException('组件文件过大');
    }

    final digest = md5.convert(bytes).toString();
    final saved = File(p.join(directory().path, '$digest.js'));
    await saved.writeAsBytes(bytes, flush: true);

    WidgetMeta meta;
    try {
      meta = await store.widgets!.meta(saved.path);
    } on FormatException catch (error) {
      throw FormatException(error.message);
    } on Object catch (error) {
      final message = '$error';
      if (message.contains('WidgetMetadata not found')) {
        throw const FormatException('不是组件脚本：没有找到 WidgetMetadata');
      }
      throw FormatException(message);
    }

    final repoId = 'repo-${DateTime.now().microsecondsSinceEpoch}';
    final repo = WidgetRepo(
      id: repoId,
      address: input,
      name: (name ?? '').trim().isEmpty ? meta.title : name!.trim(),
      localPath: saved.path,
      widgetIds: [meta.id],
    );
    final widget = WidgetInfo(
      id: meta.id,
      repoId: repoId,
      scriptPath: saved.path,
      title: meta.title,
      description: meta.description,
      version: meta.version,
      author: meta.author,
      modules: [
        for (final module in meta.modules)
          WidgetModule(
            id: module.id,
            title: module.title,
            functionName: module.functionName,
            type: module.type,
          ),
      ],
    );

    final allRepos = repos(store)..removeWhere((r) => r.address == input);
    final allWidgets = widgets(store)..removeWhere((w) => w.id == widget.id);
    allRepos.add(repo);
    allWidgets.add(widget);
    await _write(store, repos: allRepos, widgetItems: allWidgets);
    return repo;
  }

  static Future<WidgetRepo?> _importIndex(
    AppStore store,
    Object? data, {
    String? name,
  }) async {
    final entries = data is Map ? data['widgets'] ?? data['repos'] : data;
    if (entries is! List || entries.isEmpty) {
      throw const FormatException('仓库索引里没有组件');
    }
    WidgetRepo? first;
    for (final entry in entries) {
      final address = entry is String
          ? entry
          : (entry is Map ? '${entry['url'] ?? entry['address'] ?? ''}' : '');
      if (address.isEmpty || address == 'null') continue;
      final entryName = entry is Map ? '${entry['name'] ?? entry['title'] ?? ''}' : '';
      final repo = await importAddress(
        store,
        address,
        name: entryName.isEmpty ? name : entryName,
      );
      first ??= repo;
    }
    if (first == null) throw const FormatException('仓库索引里没有组件');
    return first;
  }

  static Future<void> deleteRepo(AppStore store, String id) async {
    final repo = repos(store).firstWhere(
      (candidate) => candidate.id == id,
      orElse: () => const WidgetRepo(id: '', address: ''),
    );
    final remaining = repos(store)..removeWhere((r) => r.id == id);
    final items = widgets(store)
      ..removeWhere((widget) => widget.repoId == id);
    await _write(store, repos: remaining, widgetItems: items);
    if (repo.localPath.isNotEmpty &&
        !items.any((widget) => widget.scriptPath == repo.localPath)) {
      final file = File(repo.localPath);
      if (file.existsSync()) await file.delete();
    }
  }

  static Future<void> setWidgetGroup(
    AppStore store,
    String widgetId,
    String group,
  ) async {
    final items = widgets(store);
    final index = items.indexWhere((widget) => widget.id == widgetId);
    if (index < 0) return;
    items[index] = items[index].copyWith(group: group.trim());
    await _write(store, widgetItems: items);
  }

  static Future<void> setProxy(AppStore store, WidgetProxy value) async {
    await _write(store, proxy: value);
    await store.widgets?.applyProxy(value);
  }

  static Future<List<int>> _fetch(String url) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FormatException('组件地址返回 HTTP ${response.statusCode}');
      }
      return await response.fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('组件地址打不开：$error');
    } finally {
      client.close();
    }
  }

  static bool _looksLikeJson(List<int> bytes) {
    final head = utf8
        .decode(bytes.length > 64 ? bytes.sublist(0, 64) : bytes, allowMalformed: true)
        .trimLeft();
    return head.startsWith('{') || head.startsWith('[');
  }

  static Future<void> _write(
    AppStore store, {
    List<CustomPage>? pages,
    String? homePageId,
    List<WidgetRepo>? repos,
    List<WidgetInfo>? widgetItems,
    WidgetProxy? proxy,
  }) async {
    final settings = store.settings;
    await store.updateSettings(
      settings.copyWith(
        customPages: pages == null
            ? settings.customPages
            : [for (final page in pages) page.toJson()],
        homePageId: homePageId ?? settings.homePageId,
        widgetRepos: repos == null
            ? settings.widgetRepos
            : [for (final repo in repos) repo.toJson()],
        widgetItems: widgetItems == null
            ? settings.widgetItems
            : [for (final widget in widgetItems) widget.toJson()],
        // 代理按原版不进备份，所以这里只写内存设置与宿主，不写 prefs。
        widgetProxy: proxy == null ? settings.widgetProxy : proxy.toJson(),
      ),
    );
  }
}
