import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/main.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/services/widgets/widget_center.dart';
import 'package:lai_cui_ba/services/widgets/widget_models.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('自定义页面能设为首页，也能从设置里改回去', (tester) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await AppStore.load();
    await WidgetCenter.savePage(
      store,
      const CustomPage(id: 'p1', name: '我的页面'),
    );
    await WidgetCenter.setHomePage(store, 'p1');
    expect(WidgetCenter.homePage(store)?.name, '我的页面');

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));

    // Shell is now showing the custom page, not the source's own rails.
    expect(find.text('这个页面还没有组件'), findsOneWidget);

    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页与导航'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义页面'));
    await tester.pumpAndSettle();

    expect(find.text('我的页面'), findsOneWidget);
    expect(find.text('当前首页'), findsOneWidget);

    // Tapping the current page toggles it off; the shell goes back to the
    // source's own rails instead of showing a page that no longer exists.
    await tester.tap(find.text('我的页面'));
    await tester.pumpAndSettle();
    expect(WidgetCenter.homePage(store), isNull);
  });

  testWidgets('新建页面走真正的编辑器，保存后设置里能看到', (tester) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await AppStore.load();
    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页与导航'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义页面'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建页面'));
    await tester.pumpAndSettle();

    expect(find.text('新建页面'), findsWidgets);
    expect(find.text('页面名称'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '周末首页');
    await tester.tap(find.text('保存').first);
    await tester.pumpAndSettle();

    expect(find.text('周末首页'), findsOneWidget);
    expect(WidgetCenter.pages(store).single.name, '周末首页');
  });

  testWidgets('删除页面后首页回到资源自己的片单', (tester) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await AppStore.load();
    await WidgetCenter.savePage(
      store,
      const CustomPage(id: 'p1', name: '我的页面'),
    );
    await WidgetCenter.setHomePage(store, 'p1');
    await WidgetCenter.deletePage(store, 'p1');
    expect(WidgetCenter.homePage(store), isNull);
    expect(WidgetCenter.pages(store), isEmpty);
  });
}
