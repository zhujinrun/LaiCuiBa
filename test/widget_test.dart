import 'dart:ui' show Size;

import 'package:flutter/material.dart' show Icons, TextField;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/main.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/ui/shell.dart';

void main() {
  testWidgets('shell renders sidebar groups and hero headline', (tester) async {
    tester.view.physicalSize = const Size(1360, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.byType(Shell), findsOneWidget);
    expect(find.text('LaiCuiBa'), findsOneWidget);
    for (final label in [
      '媒体库',
      '来源',
      '列表',
      '其他',
      '首页',
      '资源',
      '收藏',
      '历史',
      '设置',
    ]) {
      expect(
        find.text(label),
        findsWidgets,
        reason: 'sidebar label "$label" missing',
      );
    }
    expect(find.text('继续观看'), findsOneWidget);
  });

  testWidgets('favorites page shows folder chips and poster grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1360, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));

    // Navigate to the favourites page via the sidebar.
    await tester.tap(find.text('收藏').first);
    await tester.pumpAndSettle();

    // Folder filter chips: 「全部 1」 + 「好看的电影 1」.
    expect(find.text('全部 1'), findsOneWidget);
    expect(find.text('好看的电影 1'), findsWidgets);

    // The seeded favourite title is shown as a poster card.
    expect(find.text('欢迎来龙餐馆'), findsOneWidget);
  });

  testWidgets('history row opens the detail page with the resume episode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));

    await tester.tap(find.text('历史').first);
    await tester.pumpAndSettle();

    // The seeded history row is 尚公主 第39集; tapping it pushes the detail page.
    await tester.tap(find.text('尚公主'));
    await tester.pumpAndSettle();

    expect(find.text('选集'), findsOneWidget);
    expect(find.text('演员阵容'), findsOneWidget);
    expect(find.text('分类'), findsOneWidget);
    // Resume button points at the episode the history row carries.
    expect(find.text('继续 第39集'), findsOneWidget);
    // The 21-40 range is selected because episode 39 lives there.
    expect(find.text('21-40'), findsOneWidget);
    expect(find.text('共 40 集'), findsOneWidget);

    // Back returns to the history page, not to the home page.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('清空'), findsOneWidget);
    expect(find.text('选集'), findsNothing);
  });

  testWidgets('search opens from the header and 取消 returns to the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));

    // The collapsed field in the header opens the mode.
    await tester.tap(find.text('搜索...'));
    await tester.pumpAndSettle();

    expect(find.text('全网搜索影视'), findsOneWidget);
    expect(find.text('搜索影视'), findsOneWidget);
    expect(
      find.text('会同时搜索影视源里的全部站点，结果按平台分组。'),
      findsOneWidget,
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // Back on the home feed: the explainer is gone and the hero is back.
    expect(find.text('搜索影视'), findsNothing);
    expect(find.text('继续观看'), findsOneWidget);
  });

  testWidgets('a committed query groups results by site and 严格 filters them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));

    await tester.tap(find.text('搜索...'));
    await tester.pumpAndSettle();

    // Typing shows the drop-down, not results.
    await tester.enterText(find.byType(TextField), '尚');
    await tester.pumpAndSettle();
    expect(find.text('尚公主'), findsWidgets);
    expect(find.text('选集'), findsNothing);

    // Enter commits it.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('「盘」 玩偶'), findsWidgets);
    expect(find.text('第40集(全)'), findsWidgets);

    // 严格 turns 尚 into an exact-title match, which nothing satisfies.
    await tester.tap(find.text('严格'));
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关影视'), findsOneWidget);
    expect(find.text('第40集(全)'), findsNothing);
  });
}
