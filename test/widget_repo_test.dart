import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/core/store_scope.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/services/widgets/widget_center.dart';
import 'package:lai_cui_ba/services/widgets/widget_models.dart';
import 'package:lai_cui_ba/services/widgets/widget_runtime.dart';
import 'package:lai_cui_ba/ui/custom/section_data.dart';
import 'package:lai_cui_ba/ui/custom/widget_search_dialog.dart';
import 'package:lai_cui_ba/ui/custom/widgets_settings_page.dart';

class _FakeRuntime implements WidgetRuntimeApi {
  Map<String, dynamic>? lastParams;

  @override
  Future<WidgetMeta> meta(String scriptPath) async => const WidgetMeta(
    id: 'fixture_widget',
    title: '测试组件',
    description: '本地夹具',
    modules: [
      WidgetModuleMeta(
        id: 'popular',
        title: '热门',
        functionName: 'getPopular',
        type: 'media_list',
        params: [
          {'name': 'keyword', 'label': '关键词', 'type': 'string'},
        ],
      ),
    ],
  );

  @override
  Future<WidgetLoadResult> load(
    String scriptPath,
    String functionName,
    Map<String, dynamic> params,
  ) async {
    if (functionName != 'getPopular') throw StateError('function not found');
    lastParams = params;
    return const WidgetLoadResult(
      items: [
        {
          'id': 'fixture-1',
          'title': '夹具影片一',
          'image': 'https://example.com/1.webp',
          'mediaType': 'movie',
          'videoUrl': 'https://example.com/1.m3u8',
        },
        {
          'id': 'fixture-2',
          'title': '夹具影片二',
          'link': 'https://example.com/detail/2',
        },
      ],
      logs: ['widget fixture page 1'],
    );
  }

  @override
  Future<WidgetDetail?> detail(String scriptPath, String link) async =>
      const WidgetDetail(
        title: '夹具详情',
        lines: [WidgetLine(name: '组件', url: 'https://example.com/detail.m3u8')],
      );

  @override
  Future<void> applyProxy(WidgetProxy proxy) async {}

  @override
  String get recentLog => '[组件] widget fixture page 1';

  @override
  Future<void> dispose() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('本地脚本导入成仓库，分组/删除都改的是本机数据', () async {
    final store = await AppStore.load();
    store.widgets = _FakeRuntime();

    final repo = await WidgetCenter.importAddress(
      store,
      'test/fixtures/widget_sample.js',
    );
    expect(repo, isNotNull);
    expect(repo!.displayName, '测试组件');
    expect(WidgetCenter.widgets(store).single.modules.single.functionName, 'getPopular');

    await WidgetCenter.setWidgetGroup(store, 'fixture_widget', '影视');
    expect(WidgetCenter.widgets(store).single.group, '影视');

    await WidgetCenter.deleteRepo(store, repo.id);
    expect(WidgetCenter.repos(store), isEmpty);
    expect(WidgetCenter.widgets(store), isEmpty);
  });

  test('组件区域拿到组件片单；组件被删后如实说清', () async {
    final store = await AppStore.load();
    store.widgets = _FakeRuntime();
    await WidgetCenter.importAddress(
      store,
      'test/fixtures/widget_sample.js',
    );

    const section = PageSection(
      id: 's',
      source: SectionSource.widget,
      widgetId: 'fixture_widget',
      moduleId: 'popular',
    );
    final data = await SectionDataLoader.load(store, section);
    expect(data.failed, isFalse);
    expect(data.items.first.title, '夹具影片一');
    expect(data.items.length, 2);
    expect(
      data.items.first.playLines.single.episodes.single.url,
      'https://example.com/1.m3u8',
    );

    final linkItem = data.items.last;
    expect(linkItem.id, 'https://example.com/detail/2');
    expect(linkItem.siteKey, 'widget:fixture_widget');
    final detail = await store.detailReal(linkItem);
    expect(detail?.playLines.single.episodes.single.url, 'https://example.com/detail.m3u8');
    expect(detail?.title, '夹具详情');

    await WidgetCenter.deleteRepo(store, WidgetCenter.repos(store).single.id);
    final gone = await SectionDataLoader.load(store, section);
    expect(gone.error, '组件仓库或数据源已被删除');
  });

  test('搜索参数按组件元数据生成并原样传给函数', () async {
    final store = await AppStore.load();
    final runtime = _FakeRuntime();
    store.widgets = runtime;
    await WidgetCenter.importAddress(
      store,
      'test/fixtures/widget_sample.js',
    );
    final widget = WidgetCenter.widgets(store).single;
    expect(widget.modules.single.params.single['name'], 'keyword');

    const section = PageSection(
      id: 's',
      source: SectionSource.widget,
      widgetId: 'fixture_widget',
      moduleId: 'popular',
      params: {'keyword': '海'},
    );
    expect(PageSection.fromJson(section.toJson()).params['keyword'], '海');
    await SectionDataLoader.load(store, section);
    expect(runtime.lastParams?['keyword'], '海');
  });

  test('代理只在本机，不进备份', () async {
    final store = await AppStore.load();
    store.widgets = _FakeRuntime();
    await WidgetCenter.setProxy(
      store,
      const WidgetProxy(url: 'http://127.0.0.1:7890'),
    );
    expect(WidgetCenter.proxy(store).url, 'http://127.0.0.1:7890');
    expect(
      jsonEncode(store.exportBundle()['settings']).contains('widgetProxy'),
      isFalse,
    );
    expect(WidgetCenter.recentLogs(store).single, contains('widget fixture'));
  });

  test('JSON 仓库索引会逐项导入', () async {
    final dir = Directory.systemTemp.createTempSync('lcb_widget_index_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final index = File('${dir.path}${Platform.pathSeparator}index.json');
    await index.writeAsString(
      jsonEncode([
        {
          'url': 'test/fixtures/widget_sample.js',
          'name': '索引里的组件',
        },
      ]),
    );

    final store = await AppStore.load();
    store.widgets = _FakeRuntime();
    await WidgetCenter.importAddress(store, index.path);
    expect(WidgetCenter.repos(store).single.displayName, '索引里的组件');
  });

  testWidgets('设置页摆出组件仓库入口与空态', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await AppStore.load();
    store.widgets = _FakeRuntime();
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: CustomPagesSettings()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('组件仓库与自定义首页页面'), findsOneWidget);
    expect(find.text('导入组件仓库'), findsOneWidget);
    expect(find.text('选择组件脚本'), findsOneWidget);
    expect(find.text('还没有导入组件仓库'), findsOneWidget);
  });

  testWidgets('组件搜索表单按模块参数生成，并把结果列出来', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await AppStore.load();
    store.widgets = _FakeRuntime();
    await tester.runAsync(
      () => WidgetCenter.importAddress(
        store,
        'test/fixtures/widget_sample.js',
      ),
    );
    final widget = WidgetCenter.widgets(store).single;
    const section = PageSection(
      id: 's',
      source: SectionSource.widget,
      widgetId: 'fixture_widget',
      moduleId: 'popular',
    );

    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => WidgetSearchDialog(
                  section: section,
                  widget: widget,
                  module: widget.modules.single,
                ),
              ),
                child: const Text('打开搜索'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开搜索'));
    await tester.pumpAndSettle();
    expect(find.text('关键词'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '海');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('夹具影片一'), findsOneWidget);
    expect(find.text('夹具影片二'), findsOneWidget);
  });
}
