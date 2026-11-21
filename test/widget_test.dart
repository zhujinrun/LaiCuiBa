import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoSwitch;
import 'package:flutter/material.dart'
    show CircularProgressIndicator, Icons, TextField, ValueKey, Wrap;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/main.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/backup.dart';
import 'package:lai_cui_ba/services/demo_data.dart' as demo;
import 'package:lai_cui_ba/services/source_probe.dart';
import 'package:lai_cui_ba/services/spider_session.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/ui/shell.dart';

/// Stands in for the cat host's detail action: fills in the fields a result row
/// cannot carry (episode list, cast, genres) the way a source does. The detail
/// page has to render a real record, and the fixtures that used to supply one
/// are off.
Future<MediaItem?> fakeDetail(MediaItem item) async => MediaItem(
      id: item.id,
      title: item.title,
      image: item.image,
      latest: '第40集',
      year: 2026,
      area: '中国大陆',
      categories: const ['剧情', '爱情', '古装'],
      overview: '由测试替身提供的简介，用来验证详情页渲染的是源记录。',
      actors: const ['孟子义', '李昀锐', '吴汉坤'],
      episodes: [for (var i = 1; i <= 40; i++) '第$i集'],
      siteKey: item.siteKey,
      sourceName: item.sourceName,
    );

/// Stands in for the cat host's search action: one group per site, one hit per
/// group. [strict] copies the source's own rule -- only an exact title matches.
Stream<SpiderSearchSite>? Function(String, {bool strict}) fakeSearch(
  List<String> sites, {
  String title = '尚公主',
  String latest = '第40集(全)',
}) {
  return (String keyword, {bool strict = false}) async* {
    if (keyword.trim().isEmpty) return;
    if (strict && keyword != title) return;
    if (!title.contains(keyword)) return;
    for (final site in sites) {
      yield SpiderSearchSite(
        site: site,
        items: [MediaItem(id: 'v-$site', title: title, latest: latest)],
      );
    }
  };
}

void main() {
  // The app does not seed a sample history or favourite any more; these tests
  // need rows to exercise those pages, so they opt in explicitly.
  setUpAll(() => AppStore.seedSampleUserData = true);

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
    // The chip follows the choice. The cards do too, but they are drawn from
    // whatever the site answers with, so there is nothing here to pin until a
    // source answers -- the fixtures that used to stand in are off.
    expect(find.text('「盘」夸克'), findsOneWidget);
    expect(find.text('「直」荐片'), findsNothing);
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
    // The detail page opens on the row's own fields, then swaps in the record
    // its site returns. Without the cat host on this machine that call is
    // stubbed, which is the same shape the real one has.
    store.detailStub = fakeDetail;

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
    // Two sites answer, which is enough to prove the rows are grouped by site.
    store.searchStub = fakeSearch(const ['「盘」夸克', '「直」荐片']);

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));

    await tester.tap(find.text('搜索...'));
    await tester.pumpAndSettle();

    // Typing shows the drop-down, not results.
    await tester.enterText(find.byType(TextField), '尚');
    await tester.pumpAndSettle();
    expect(find.text('选集'), findsNothing);

    // Enter commits it. 严格 defaults on, so the inexact 尚 matches nothing.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关影视'), findsOneWidget);

    // Turning 严格 off makes 尚 a contains-match, which hits 尚公主.
    await tester.tap(find.text('严格'));
    await tester.pumpAndSettle();

    expect(find.text('全部'), findsOneWidget);
    // Site chips and result tags both render the names the source reports,
    // prefix included -- the UI no longer invents a 「盘」 of its own.
    expect(find.textContaining('「盘」'), findsWidgets);
    expect(find.text('第40集(全)'), findsWidgets);

    // Re-enabling 严格 drops the inexact match again.
    await tester.tap(find.text('严格'));
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关影视'), findsOneWidget);
    expect(find.text('第40集(全)'), findsNothing);
  });

  testWidgets('the site expand button reveals the sites folded into 还有 N 个站点', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    // Twelve sites answer, so the chip row has a tail to fold.
    store.searchStub = fakeSearch([
      for (final site in store.sources.first.sites.take(12)) site.name,
    ]);

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));

    await tester.tap(find.text('搜索...'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '尚公主');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Collapsed: the tail reports how many sites are hidden, and the chip row
    // scrolls horizontally (no Wrap).
    expect(find.textContaining('还有'), findsOneWidget);

    // Tap the expand chevron to reveal every site on wrapped rows.
    await tester.tap(find.byIcon(CupertinoIcons.chevron_down));
    await tester.pumpAndSettle();
    expect(find.textContaining('还有'), findsNothing);
    // The chip row switched to a wrapping layout, so all sites are now on
    // screen rather than hidden behind a horizontal scroll.
    expect(find.byType(Wrap), findsOneWidget);

    // And it collapses back.
    await tester.tap(find.byIcon(CupertinoIcons.chevron_up));
    await tester.pumpAndSettle();
    expect(find.textContaining('还有'), findsOneWidget);
    expect(find.byType(Wrap), findsNothing);
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
    store.searchStub = fakeSearch(const ['「直」荐片']);
    store.detailStub = fakeDetail;

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));

    await tester.tap(find.text('搜索...'));
    await tester.pumpAndSettle();

    // 严格 defaults on, so an exact title is needed to land a result.
    await tester.enterText(find.byType(TextField), '尚公主');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // The result row is tappable and must push the detail page (regression:
    // the search overlay used to stay on top, so this tap did nothing). The
    // first 尚公主 is the text in the search field; the result row is the next.
    await tester.tap(find.text('尚公主').at(1));
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

  testWidgets('the source card shows the measured title count', (tester) async {
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

    // The seeded source carries the original's cached figure, so the card
    // prints 部 rather than the 59 sites the config declares.
    expect(find.text('当前使用 · 58 部'), findsOneWidget);

    // A check that measured something else takes over without a relaunch.
    await store.applyProbe(
      store.sources.first.id,
      const ProbeReport(latencyMs: 700, movieCount: 12, showCount: 3, siteCount: 59),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前使用 · 12 部'), findsOneWidget);
    expect(find.text('0.7s'), findsOneWidget);
  });

  testWidgets('a mounted source owns 首页, and says when its library is empty', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    await store.addSource(
      const SourceInfo(
        id: 'emby-home',
        type: 'emby',
        name: '客厅 Emby',
        url: 'http://127.0.0.1:9',
        username: 'lxy',
        token: 'tok',
        tokenUserId: 'u1',
      ),
    );
    await store.selectSource('emby-home');

    await tester.pumpWidget(LcbApp(store: store));
    // The library fetch cannot succeed under the test binding (every request is
    // answered with 400 without connecting), which is fine: the point is that
    // the home page stops presenting bundled fixtures as the user's library.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));

    // No fixture rail survives (its section header is what proves it -- a
    // history row may legitimately still say 尚公主 in 继续观看), and the page
    // says whose empty library this is instead.
    expect(find.text(demo.homeSections.first.title), findsNothing);
    expect(find.text('客厅 Emby 的影片库里还没有内容'), findsOneWidget);
  });

  testWidgets('a 猫源 that cannot answer says so on 首页', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    // The seeded 豆儿猫源 is a bundle subscription, so the home page asks it for
    // rails. No session is attached under the test binding, so it cannot answer.
    expect(store.hasSpiderHome, isTrue);

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));

    // No fixture stands in for the missing answer: the page names the source
    // that failed, offers a retry, and keeps the spinner out of the way.
    expect(find.text(demo.homeSections.first.title), findsNothing);
    expect(find.text('豆儿猫源 没有答上来'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('的首页没有取到片单'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('with no source at all, 首页 points at 资源 instead of fixtures', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    for (final source in [...store.sources]) {
      await store.removeSource(source.id);
    }

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text(demo.homeSections.first.title), findsNothing);
    expect(find.text('还没有可用的来源'), findsOneWidget);
  });

  testWidgets('the Emby form refuses to save a mount it could not log in to', (
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

    // The test binding answers every HTTP request with 400 without connecting,
    // so the login cannot succeed here -- which is the case worth locking down:
    // a mount that never authenticated must not be written to the source list
    // as if it were ready.
    expect(store.sources.where((s) => s.type == 'emby'), isEmpty);
    expect(find.byKey(const ValueKey('server-form-error')), findsOneWidget);
    expect(find.text('添加'), findsOneWidget);
  });

  testWidgets('the Emby form asks for credentials before trying to log in', (
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
    await tester.enterText(fields.at(1), 'http://192.168.1.10:8096');
    await tester.pump();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(store.sources.where((s) => s.type == 'emby'), isEmpty);
    expect(find.text('要填账号和密码才能登录，密码不会被保存'), findsOneWidget);
  });
}
