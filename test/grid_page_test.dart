import 'dart:ui' show Size;

import 'package:flutter/material.dart' show MaterialApp, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/core/store_scope.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/ui/pages/grid_page.dart';

import 'support/fake_py_host.dart';

/// 分类页：首页一条分区点「查看全部」之后看到的东西。
///
/// 一组测分页真的按 page 请求、并且到底就停；一组测第一页失败时说清楚而不是
/// 摆一个空网格。
void main() {
  Future<AppStore> storeWith(FakePyHost host, {String homeSite = 'a'}) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    store.scripts = FakeScriptSources(host);
    await store.addSource(
      SourceInfo(
        id: 'py-grid',
        type: 'py',
        name: '分页源',
        url: r'D://sources//main.py',
        homeSite: homeSite,
        sites: const [
          SiteInfo(key: 'a', name: '甲站', api: 'a.py'),
          SiteInfo(key: 'b', name: '乙站', api: 'b.py'),
        ],
      ),
    );
    await store.selectSource('py-grid');
    return store;
  }

  Widget host(AppStore store, Widget child) => MaterialApp(
    home: StoreScope(store: store, child: child),
  );

  testWidgets('分页按源给的页数取完就停', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = _PagedHost();
    final store = await storeWith(fake);

    await tester.pumpWidget(host(store, const GridPage(title: '电影', typeId: '1')));
    await tester.pump();

    // 第一页两部。
    expect(find.text('第1页甲'), findsOneWidget);
    expect(find.text('第1页乙'), findsOneWidget);
    expect(find.text('第2页丙'), findsNothing);

    // 滚到底部触发第二页；源的 pagecount=2，所以之后就没了。
    await tester.drag(find.byType(GridPage), const Offset(0, -4000));
    await tester.pump();
    await tester.pump();

    expect(find.text('第2页丙'), findsOneWidget);
    expect(find.text('共 3 部'), findsOneWidget);
    // 只问过两页：到页数上限就停，不空转。
    expect(fake.pages, ['1', '2']);

    // 再滚也不会有第三页。
    await tester.drag(find.byType(GridPage), const Offset(0, -4000));
    await tester.pump();
    expect(fake.pages, ['1', '2']);
  });

  testWidgets('面板挑的条件原样交给源', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = _PagedHost();
    final store = await storeWith(fake);

    await tester.pumpWidget(
      host(
        store,
        const GridPage(
          title: '电影',
          typeId: '1',
          filters: {'class': '喜剧', 'by': 'score'},
        ),
      ),
    );
    await tester.pump();

    // TVBox 源把条件放在 extend 里；filter 要一起置真，源才会用。
    expect(fake.lastFilter, isTrue);
    expect(fake.lastExtend, {'class': '喜剧', 'by': 'score'});
    expect(find.text('第1页甲'), findsOneWidget);
  });

  testWidgets('没有宿主时第一页直接说加载失败，并给重试', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await storeWith(_PagedHost());
    // 宿主没起来：这不是「这个分类没有片单」，不能说成空分类。
    store.scripts = null;

    await tester.pumpWidget(host(store, const GridPage(title: '电影', typeId: '1')));
    await tester.pump();

    expect(find.text('加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('下没有取到片单'), findsNothing);
  });
}

/// 两页的分类：第一次问给两部、说共两页，第二次问给一部。
class _PagedHost extends FakePyHost {
  _PagedHost() : super(bodies: const {});

  /// 每次 category 请求带上的页码，按顺序记下来。
  final List<String> pages = [];

  /// The last `[filter, extend]` a category call carried.
  bool? lastFilter;
  Object? lastExtend;

  @override
  Future<String> call({
    required String key,
    required String path,
    required String method,
    String ext = '',
    List<Object?> args = const [],
  }) async {
    calls.add(method);
    if (method != 'category') throw StateError('没有实现 $method');
    final page = '${args[1] ?? '1'}';
    pages.add(page);
    lastFilter = args[2] as bool?;
    lastExtend = args[3];
    if (page == '2') {
      return '{"page":2,"pagecount":2,"total":3,"list":[{"vod_id":"3",'
          '"vod_name":"第2页丙","vod_pic":"http://example.invalid/c.jpg"}]}';
    }
    return '{"page":1,"pagecount":2,"total":3,"list":['
        '{"vod_id":"1","vod_name":"第1页甲","vod_pic":"http://example.invalid/a.jpg"},'
        '{"vod_id":"2","vod_name":"第1页乙","vod_pic":"http://example.invalid/b.jpg"}]}';
  }
}
