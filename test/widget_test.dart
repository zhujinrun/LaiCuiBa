import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoSwitch;
import 'package:flutter/material.dart' show Icons, TextField;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/main.dart';
import 'package:lai_cui_ba/services/backup.dart';
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
    // The header's two chips name the real source and the site the feed was
    // drawn from; both come from the store, not from string literals.
    expect(find.text('豆儿猫源'), findsOneWidget);
    expect(find.text('「直」荐片'), findsOneWidget);
  });

  testWidgets('the site chip picks which site the feed speaks for', (
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

    await tester.tap(find.text('「直」荐片'));
    await tester.pumpAndSettle();
    expect(find.text('选择站点'), findsOneWidget);
    expect(find.textContaining('59 个可选'), findsOneWidget);

    // 59 names need a filter, not a scroll.
    await tester.enterText(find.byType(TextField).last, '夸克');
    await tester.pumpAndSettle();
    expect(find.text('「盘」夸克'), findsOneWidget);
    expect(find.text('「盘」多多'), findsNothing);

    await tester.tap(find.text('「盘」夸克'));
    await tester.pumpAndSettle();

    expect(store.sources.first.homeSite, 'nodejs_myquark');
    expect(find.text('选择站点'), findsNothing);
    // The chip and every card follow the choice.
    expect(find.text('「盘」夸克'), findsOneWidget);
    expect(find.text('「直」荐片'), findsNothing);
    expect(store.heroItems.first.siteKey, 'nodejs_myquark');
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
    // The 选集 filter row names the site the record came from.
    expect(find.text('「直」荐片'), findsOneWidget);

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
    expect(find.text('会同时搜索影视源里的全部站点，结果按平台分组。'), findsOneWidget);

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
    // Site chips and result tags both render the config's own names, prefix
    // included -- the UI no longer invents a 「盘」 of its own.
    expect(find.textContaining('「盘」'), findsWidgets);
    expect(find.text('第40集(全)'), findsWidgets);

    // 严格 turns 尚 into an exact-title match, which nothing satisfies.
    await tester.tap(find.text('严格'));
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关影视'), findsOneWidget);
    expect(find.text('第40集(全)'), findsNothing);
  });

  testWidgets('tapping a search result opens the detail page and back returns', (
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

    await tester.enterText(find.byType(TextField), '尚');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // The result row is tappable and must push the detail page (regression:
    // the search overlay used to stay on top, so this tap did nothing).
    await tester.tap(find.text('尚公主').first);
    await tester.pumpAndSettle();

    expect(find.text('选集'), findsOneWidget);
    expect(find.text('演员阵容'), findsOneWidget);

    // Back returns to the search results, not the home feed.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('选集'), findsNothing);
    expect(find.text('全部'), findsOneWidget);
  });

  testWidgets('a pasted config becomes a source whose sites feed the fan-out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    expect(store.sources, hasLength(1));

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));

    // 资源 page, then the header's + button.
    await tester.tap(find.text('资源').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.plus));
    await tester.pumpAndSettle();
    // + opens 添加资源; the paste form is one of its nine entries now.
    await tester.tap(find.text('粘贴站点 / 配置文本'));
    await tester.pumpAndSettle();
    expect(find.text('添加影视源'), findsOneWidget);

    const config = '{"sites":[{"key":"mine","name":"我的站","api":"csp_Mine"}]}';
    await tester.enterText(find.byType(TextField).last, config);
    await tester.pumpAndSettle();
    expect(find.textContaining('解析到 1 个站点'), findsOneWidget);

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    // The source landed in the list and its site reached the fan-out -- the
    // whole point of parsing locally instead of stubbing the add flow.
    expect(find.text('粘贴的源'), findsOneWidget);
    expect(store.sources, hasLength(2));
    expect(
      store.sitesForSelection(null).map((site) => site.name),
      contains('我的站'),
    );
  });

  testWidgets('silencing a site from the editor narrows the site list', (
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

    await tester.tap(find.text('资源').first);
    await tester.pumpAndSettle();

    // The card's ⋯ opens the menu; 编辑 opens the source sheet.
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('站点 59 个'), findsOneWidget);

    await tester.tap(find.text('站点 59 个'));
    await tester.pumpAndSettle();

    // Flip the first site off; the summary has to say so, otherwise the user
    // has no way to tell what actually reaches search.
    await tester.tap(find.byType(CupertinoSwitch).first);
    await tester.pumpAndSettle();
    expect(find.text('站点 59 个 · 58 个参与搜索'), findsOneWidget);
    expect(store.activeSites, hasLength(58));

    // 59 rows is a scroll without a filter; the box narrows the list and shows
    // how much of it is left.
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == '搜索站点',
      ),
      '夸克',
    );
    await tester.pumpAndSettle();
    expect(find.text('1/59'), findsOneWidget);
    expect(find.text('「盘」夸克'), findsOneWidget);
    expect(find.text('「盘」多多'), findsNothing);
  });

  testWidgets('数据与存储 reports the store and clears history for real', (
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

    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();

    // The root row already carries a real count instead of a chevron alone.
    expect(find.text('1 个源'), findsOneWidget);

    await tester.tap(find.text('数据与存储'));
    await tester.pumpAndSettle();

    // 本机数据 sums what the store holds -- 59 seeded sites, all enabled.
    expect(find.text('59 个站点'), findsOneWidget);
    expect(
      find.textContaining('59/59 个启用站点'),
      findsOneWidget,
      reason: 'the summary must show enabled / total sites',
    );
    expect(find.text('1 条'), findsOneWidget);

    // Clearing needs a confirmation, then the count, the history page and the
    // home rail all go empty together.
    await tester.tap(find.text('清空观看历史'));
    await tester.pumpAndSettle();
    expect(find.text('清空观看历史？'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(store.history, isEmpty);
    expect(find.text('0 条'), findsOneWidget);
    expect(store.continueWatching, isEmpty);
  });

  testWidgets('备份与恢复 writes a file the dialog lists', (tester) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Real files, scratch folder -- never the user's own backup directory.
    final scratch = Directory.systemTemp.createTempSync('lcb-widget-backup-');
    LcbBackup.overrideDirectory = scratch;
    addTearDown(() {
      LcbBackup.overrideDirectory = null;
      // Windows sometimes still holds the file for a moment after the write;
      // the scratch folder lives under %TEMP% either way.
      try {
        if (scratch.existsSync()) scratch.deleteSync(recursive: true);
      } on FileSystemException {
        // ignore
      }
    });

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));

    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('数据与存储'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('备份与恢复'));
    await tester.pumpAndSettle();

    expect(find.text('还没有备份'), findsOneWidget);
    expect(find.textContaining('本机共 1 个源 · 59 个站点'), findsOneWidget);

    // The export touches the real file system, which only runs inside
    // runAsync; pumpAndSettle alone would leave the future pending.
    await tester.runAsync(() async {
      await tester.tap(find.text('立即备份'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(find.text('还没有备份'), findsNothing);
    // Three places name the file: the toast, the folder hint and the row.
    expect(find.textContaining('lcb-'), findsWidgets);
    expect(scratch.listSync().whereType<File>(), hasLength(1));
  });

  testWidgets('添加资源 lists the original nine entries in three groups', (
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

    await tester.tap(find.text('资源').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.plus));
    await tester.pumpAndSettle();

    expect(find.text('添加资源'), findsOneWidget);
    for (final group in ['媒体服务器', '影视源', '从本地导入']) {
      expect(find.text(group), findsOneWidget, reason: 'missing group $group');
    }
    for (final entry in [
      'Emby 服务器',
      '飞牛影视 / Jellyfin',
      'TVBox 影视源',
      '直播频道',
      '粘贴站点 / 配置文本',
      '导入文件',
      '导入直播列表文件',
      '导入文件夹里的源',
      '从 ZIP 本地包导入',
    ]) {
      expect(find.text(entry), findsOneWidget, reason: 'missing entry $entry');
    }
  });

  testWidgets('an address-only source is stored and says what is missing', (
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

    await tester.tap(find.text('资源').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.plus));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TVBox 影视源'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).last,
      'https://example.com/config.json',
    );
    await tester.pump();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(store.sources, hasLength(2));
    final added = store.sources.last;
    expect(added.type, 'tvbox');
    expect(added.url, 'https://example.com/config.json');
    // No sites are invented: the address is all that was given.
    expect(added.sites, isEmpty);
    expect(added.homeSite, isEmpty);
    expect(find.text('未使用 · 地址待拉取'), findsOneWidget);

    // Selecting it does not make anything up either.
    await tester.tap(find.text('TVBox 影视源'));
    await tester.pumpAndSettle();
    expect(find.text('当前使用 · 待联网拉取'), findsOneWidget);
    expect(store.activeSites, isEmpty);
  });

  testWidgets('the Emby form keeps address and user, never the password', (
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

    await tester.tap(find.text('资源').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.plus));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emby 服务器'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '客厅 Emby');
    await tester.enterText(fields.at(1), 'http://192.168.1.10:8096');
    await tester.enterText(fields.at(2), 'lxy');
    await tester.enterText(fields.at(3), 'secret');
    await tester.pump();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    final added = store.sources.last;
    expect(added.type, 'emby');
    expect(added.name, '客厅 Emby');
    expect(added.url, 'http://192.168.1.10:8096');
    expect(added.username, 'lxy');
    // A password with nowhere to be exchanged for a token is not written.
    expect(added.password, isEmpty);
    expect(find.text('未连接 · lxy'), findsOneWidget);
  });
}
