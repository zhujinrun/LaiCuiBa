import 'dart:io';
import 'dart:ui' show Offset, Size;

import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoSwitch;
import 'package:flutter/material.dart'
    show CircularProgressIndicator,
        Center,
        GestureDetector,
        Icons,
        MaterialApp,
        ReorderableListView,
        Scaffold,
        SizedBox,
        Text,
        TextField,
        ValueKey,
        Wrap;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/main.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/backup.dart';
import 'package:lai_cui_ba/services/demo_data.dart' as demo;
import 'package:lai_cui_ba/services/skip_rule.dart';
import 'package:lai_cui_ba/services/source_probe.dart';
import 'package:lai_cui_ba/services/spider_session.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/services/track_choice.dart';
import 'package:lai_cui_ba/core/nav.dart';
import 'package:lai_cui_ba/core/store_scope.dart';
import 'package:lai_cui_ba/ui/pages/grid_page.dart';
import 'package:lai_cui_ba/ui/shell.dart';
import 'package:lai_cui_ba/ui/widgets/add_source_menu.dart';
import 'package:lai_cui_ba/ui/widgets/hero_banner.dart';

import 'support/fake_py_host.dart';

/// Answers 首页 per site: `path` is the site's api, so 甲站 and 乙站 can hand
/// back different rails. [emptySite] makes one of them declare no titles.
class _PerSiteHost extends FakePyHost {
  _PerSiteHost({this.emptySite}) : super(bodies: const {});

  final String? emptySite;

  @override
  Future<String> call({
    required String key,
    required String path,
    required String method,
    String ext = '',
    List<Object?> args = const [],
  }) async {
    calls.add(method);
    if (method == 'home') {
      return '{"class":[{"type_id":"1","type_name":"$path分类"}]}';
    }
    if (method == 'category') {
      if (path == emptySite) return '{"list":[]}';
      final title = path == 'a.py' ? '甲站片' : '乙站片';
      return '{"list":[{"vod_id":"$path-1","vod_name":"$title",'
          '"vod_pic":"http://example.invalid/a.jpg","vod_remarks":"HD"}]}';
    }
    throw StateError('没有实现 $method');
  }
}

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

  test('片头片尾秒数与总开关落进真实的跳过规则', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    await store.updateSettings(
      store.settings.copyWith(
        skipIntroOutro: true,
        introSkipMs: 90000,
        outroSkipMs: 30000,
      ),
    );
    expect(store.skipRule.intro, const Duration(seconds: 90));
    expect(store.skipRule.outro, const Duration(seconds: 30));
    await store.updateSettings(
      store.settings.copyWith(skipIntroOutro: false),
    );
    expect(store.skipRule.isEmpty, isTrue);
  });


  test('单剧跳过覆盖、倍速与解码模式都落到设置里', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    await store.updateSettings(
      store.settings.copyWith(
        playerRate: 1.5,
        playerButtons: 'text',
        decoderMode: 'software',
      ),
    );
    await store.setSkipOverride('三体', const SkipOverride(introMs: 30000));
    expect(store.settings.playerRate, 1.5);
    expect(store.settings.playerButtons, 'text');
    expect(store.settings.decoderMode, 'software');
    expect(store.skipOverrideCount, 1);
    await store.clearSkipOverrides();
    expect(store.skipOverrideCount, 0);
  });


  testWidgets('媒体徽章 settings show the original rows and persist switches', (
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
    await tester.tap(find.text('媒体徽章'));
    await tester.pumpAndSettle();

    expect(find.text('启用媒体徽章'), findsOneWidget);
    expect(find.text('在播放器中显示'), findsOneWidget);
    expect(find.text('随播放控件显示或隐藏'), findsOneWidget);
    expect(find.text('在资源卡片中显示'), findsOneWidget);
    expect(find.text('内置徽章'), findsOneWidget);
    expect(find.text('效果预览'), findsOneWidget);

    await tester.tap(find.text('启用媒体徽章'));
    await tester.pumpAndSettle();
    expect(store.settings.mediaBadgesEnabled, isFalse);
    await tester.tap(find.text('在播放器中显示'));
    await tester.pumpAndSettle();
    expect(store.settings.badgeInPlayer, isFalse);
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

  testWidgets('资源页默认按类型分组，第一组展开、点组标题能折叠', (tester) async {
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

    // 种子源是 TVBox：组标题在，第一组默认展开，卡片可见。
    expect(find.text('TVBox'), findsWidgets);
    expect(find.text('当前使用 · 58 部'), findsOneWidget);

    // 点组标题折叠：卡片收起，组标题还在。
    await tester.tap(find.byKey(const ValueKey('resource-group-TVBox')));
    await tester.pumpAndSettle();
    expect(find.text('当前使用 · 58 部'), findsNothing);
    expect(find.text('TVBox'), findsWidgets);
  });

  testWidgets('资源页：自定义组名覆盖按类型分组', (tester) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    await store.setSourceGroup(store.sources.first.id, '我的常用');

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.text('资源').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('resource-group-我的常用')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('resource-group-TVBox')), findsNothing);
  });

  testWidgets('资源页搜索按名字过滤，没命中时说明没找到', (tester) async {
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

    // 顶栏放大镜展开搜索条。
    await tester.tap(find.byIcon(CupertinoIcons.search).first);
    await tester.pumpAndSettle();
    expect(find.text('在 1 个资源里查找'), findsOneWidget);

    // 没命中的词：明说没有，而不是留白。
    await tester.enterText(find.byType(TextField).last, '不存在的名字');
    await tester.pumpAndSettle();
    expect(find.textContaining('没有名字、地址或站点含'), findsOneWidget);

    // 命中种子源名字里的字，卡片回来了。
    await tester.enterText(find.byType(TextField).last, store.sources.first.name);
    await tester.pumpAndSettle();
    expect(find.text('当前使用 · 58 部'), findsOneWidget);
  });

  testWidgets('资源页多选：勾选后批量删除，删完回到空态', (tester) async {
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

    // 对勾圆圈进入多选。
    await tester.tap(find.byIcon(CupertinoIcons.checkmark_circle).first);
    await tester.pumpAndSettle();
    expect(find.text('已选 0 个'), findsOneWidget);

    // 点卡片勾选一个。
    await tester.tap(find.text('当前使用 · 58 部'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 个'), findsOneWidget);

    // 删除 → 确认对话框 → 真删。
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除 1 个资源'), findsOneWidget);
    await tester.tap(find.text('删除 1 个'));
    await tester.pumpAndSettle();

    expect(store.sources, isEmpty);
    expect(find.text('还没有资源'), findsOneWidget);
  });

  testWidgets('资源页平铺视图能拖动改顺序，分组视图里不提供拖动', (tester) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    await store.addSource(
      const SourceInfo(
        id: 'second',
        type: 'webdav',
        name: '第二个源',
        url: 'https://dav.example.com',
      ),
    );
    final firstId = store.sources.first.id;

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.text('资源').last);
    await tester.pumpAndSettle();

    // 分组视图：卡片不套拖动层，拖不动（组内邻居是别的组，没有唯一含义）。
    expect(find.byType(ReorderableListView), findsNothing);

    await tester.tap(find.byIcon(CupertinoIcons.slider_horizontal_3).first);
    await tester.pumpAndSettle();
    expect(find.byType(ReorderableListView), findsOneWidget);

    // 桌面端 Flutter 默认会在每张卡 trailing 叠一个 Icons.drag_handle —
    // 截图里资源卡片右侧那两条横杠。原版没有手柄，必须关掉默认手柄、改由
    // 整卡长按拖动，各平台一致。
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    expect(list.buildDefaultDragHandles, isFalse,
        reason: '不该显示 Flutter 桌面默认的拖动横杠');
    expect(find.byIcon(Icons.drag_handle), findsNothing);

    // Android 上默认是「长按再拖」：先按住第一张卡，等长按触发后往下推过
    // 第二张卡的中点，就会换位。
    final card = find.byKey(ValueKey('resource-card-$firstId'));
    final height = tester.getSize(card).height;
    final gesture = await tester.startGesture(tester.getCenter(card));
    await tester.pump(const Duration(milliseconds: 700));
    // 分几步推：拖动层要先看到位移才真正接管，一口气 move 到底算不出来。
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(Offset(0, height / 6));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(store.sources.first.id, 'second');
    expect(store.sources.last.id, firstId);
  });

  testWidgets('资源页：组标题的 ⋯ 能改名，也能删组让资源回到类型分组', (tester) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    final id = store.sources.first.id;
    await store.setSourceGroup(id, '我的常用');

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.text('资源').last);
    await tester.pumpAndSettle();

    // 类型组没有 ⋯：名字是从类型推出来的，没得改。
    expect(
      find.byKey(const ValueKey('resource-group-menu-TVBox')),
      findsNothing,
    );

    // 改名。
    await tester.tap(find.byKey(const ValueKey('resource-group-menu-我的常用')));
    await tester.pumpAndSettle();
    expect(find.text('分组「我的常用」'), findsOneWidget);
    await tester.tap(find.text('重命名分组'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '影音');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(store.sources.first.groupName, '影音');
    expect(find.byKey(const ValueKey('resource-group-影音')), findsOneWidget);

    // 删组：资源还在，只是回到按类型分组。
    await tester.tap(find.byKey(const ValueKey('resource-group-menu-影音')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分组'));
    await tester.pumpAndSettle();
    expect(find.text('这 1 个资源不会删除，会回到按类型的分组。'), findsOneWidget);
    await tester.tap(find.text('删除分组').last);
    await tester.pumpAndSettle();

    expect(store.sources.length, 1);
    expect(store.sources.first.groupName, '');
    expect(find.byKey(const ValueKey('resource-group-TVBox')), findsOneWidget);
  });

  testWidgets('批量导入前问一次分组，留空就按类型收', (tester) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    await store.setSourceGroup(store.sources.first.id, '我的常用');

    var answer = '未回答';
    Future<void> open() async {
      answer =
          await showImportGroupForm(
            tester.element(find.text('开')),
            count: 3,
            existing: store.customGroups,
          ) ??
          '取消了';
    }

    await tester.pumpWidget(
      MaterialApp(
        home: StoreScope(
          store: store,
          child: Center(
            child: GestureDetector(onTap: open, child: const Text('开')),
          ),
        ),
      ),
    );

    await tester.tap(find.text('开'));
    await tester.pumpAndSettle();
    expect(
      find.text('这批 3 个资源可以放进同一个分组，留空则继续按资源类型自动分组。'),
      findsOneWidget,
    );

    // 已有组名一键填：不用重新打一遍，也不会打错一个字分出两个组。
    await tester.tap(find.text('我的常用'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入 3 个资源'));
    await tester.pumpAndSettle();
    expect(answer, '我的常用');

    // 留空＝按类型分组。
    await tester.tap(find.text('开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入 3 个资源'));
    await tester.pumpAndSettle();
    expect(answer, '');
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

  testWidgets('a Python source owns 首页 and draws its own rails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    final host = FakePyHost(
      bodies: {
        'home': (_) => '{"class":[{"type_id":"1","type_name":"纪录片"}]}',
        'category': (_) =>
            '{"list":[{"vod_id":"1001","vod_name":"夹具电影",'
                '"vod_pic":"http://example.invalid/m.jpg","vod_remarks":"HD"}]}',
      },
    );
    store.scripts = FakeScriptSources(host);
    await store.addSource(
      const SourceInfo(
        id: 'py-home',
        type: 'py',
        name: '本地 Python 源',
        url: r'D://sources//main.py',
      ),
    );
    await store.selectSource('py-home');

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));

    // The rail header is the category the source declared, and the card is the
    // title it answered with -- not a fixture that happens to look similar.
    expect(find.text('纪录片'), findsWidgets);
    expect(find.text('夹具电影'), findsWidgets);
    // The bundled rails are off; their first title would give them away.
    expect(find.text(demo.homeSections.first.items.first.title), findsNothing);
  });

  testWidgets('回首页先用上次的片单铺满，再在后台重取一次', (tester) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    final host = FakePyHost(
      bodies: {
        'home': (_) => '{"class":[{"type_id":"1","type_name":"纪录片"}]}',
        'category': (_) =>
            '{"list":[{"vod_id":"1001","vod_name":"夹具电影",'
                '"vod_pic":"http://example.invalid/m.jpg","vod_remarks":"HD"}]}',
      },
    );
    store.scripts = FakeScriptSources(host);
    await store.addSource(
      const SourceInfo(
        id: 'py-home',
        type: 'py',
        name: '本地 Python 源',
        url: r'D://sources//main.py',
      ),
    );
    await store.selectSource('py-home');

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('夹具电影'), findsWidgets);
    final firstRound = host.calls.where((m) => m == 'category').length;

    // 走到别的页面再回来：这一次不能又变成一片白等源回答。
    await tester.tap(find.text('资源').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页').last);
    await tester.pump();

    expect(find.text('夹具电影'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // 后台那一次真的发生了，只是没挡住页面。
    await tester.pumpAndSettle();
    expect(
      host.calls.where((m) => m == 'category').length,
      greaterThan(firstRound),
    );
  });

  testWidgets('重取失败时旧片单留着，并说清这是上次的', (tester) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    final host = FakePyHost(
      bodies: {
        'home': (_) => '{"class":[{"type_id":"1","type_name":"纪录片"}]}',
        'category': (_) =>
            '{"list":[{"vod_id":"1001","vod_name":"夹具电影",'
                '"vod_pic":"http://example.invalid/m.jpg","vod_remarks":"HD"}]}',
      },
    );
    store.scripts = FakeScriptSources(host);
    await store.addSource(
      const SourceInfo(
        id: 'py-home',
        type: 'py',
        name: '本地 Python 源',
        url: r'D://sources//main.py',
      ),
    );
    await store.selectSource('py-home');

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('夹具电影'), findsWidgets);

    // 源这会儿答不上来了。
    host.bodies['category'] = (_) => throw StateError('站点今天挂了');

    await tester.tap(find.text('资源').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页').last);
    await tester.pumpAndSettle();

    // 旧的片单还在，并且明说这是上次的，没有假装刚取到。
    expect(find.text('夹具电影'), findsWidgets);
    expect(find.textContaining('下面是上次的片单'), findsOneWidget);
  });

  testWidgets('首页大图的播放按钮真的开播', (tester) async {
    MediaItem? played;
    await tester.pumpWidget(
      MaterialApp(
        home: LcbPlayScope(
          play: (item, {int? episodeIndex}) => played = item,
          child: const Scaffold(
            body: HeroBanner(items: [MediaItem(id: 'hero-1', title: '封面片')]),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('播放'));
    await tester.pump();

    // 以前这个按钮的 onTap 是空的：首页最显眼的按钮按下去什么都不发生。
    expect(played?.id, 'hero-1');

    // 轮播的 7 秒定时器要走完，否则测试结束会报未清理的 Timer。
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('首页分区的查看全部打开那个分类的网格页', (tester) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    store.scripts = FakeScriptSources(
      FakePyHost(
        bodies: {
          'home': (_) => '{"class":[{"type_id":"7","type_name":"纪录片"}]}',
          'category': (_) =>
              '{"list":[{"vod_id":"1001","vod_name":"夹具电影",'
                  '"vod_pic":"http://example.invalid/m.jpg"}]}',
        },
      ),
    );
    await store.addSource(
      const SourceInfo(
        id: 'py-grid-home',
        type: 'py',
        name: '本地 Python 源',
        url: r'D://sources//main.py',
      ),
    );
    await store.selectSource('py-grid-home');

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));

    // 分区的「查看全部」以前是空回调，点下去什么都不发生。
    await tester.tap(find.text('查看全部').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(GridPage), findsOneWidget);
    expect(find.text('纪录片'), findsWidgets);
    expect(find.text('夹具电影'), findsWidgets);
  });

  testWidgets('换站点之后首页换成那个站的片单', (tester) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    final host = _PerSiteHost();
    final scripts = FakeScriptSources(host);
    store.scripts = scripts;
    await store.addSource(
      const SourceInfo(
        id: 'py-two-sites',
        type: 'py',
        name: '双站源',
        url: r'D://sources//main.py',
        homeSite: 'a',
        sites: [
          SiteInfo(key: 'a', name: '甲站', api: 'a.py'),
          SiteInfo(key: 'b', name: '乙站', api: 'b.py'),
        ],
      ),
    );
    await store.selectSource('py-two-sites');

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));

    // 首页按 homeSite 取：一开始是甲站。
    expect(find.text('甲站片'), findsWidgets);
    expect(find.text('乙站片'), findsNothing);
    expect(scripts.asked.last.key, 'a');

    // 顶栏换站之后，页面必须重新问一次源 —— 之前这里只认源 id，换了站
    // 片单一点都不动。
    await store.selectHomeSite('b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('乙站片'), findsWidgets);
    expect(find.text('甲站片'), findsNothing);
    expect(scripts.asked.last.key, 'b');
    // 顶栏也跟着换成新站名，页面上下的说法一致。
    expect(find.text('乙站'), findsOneWidget);
  });

  testWidgets('一个站没有片单时说清楚，并给出换站入口', (tester) async {
    tester.view.physicalSize = const Size(1920, 1040);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    store.scripts = FakeScriptSources(_PerSiteHost(emptySite: 'a.py'));
    await store.addSource(
      const SourceInfo(
        id: 'py-empty-site',
        type: 'py',
        name: '空站源',
        url: r'D://sources//main.py',
        homeSite: 'a',
        sites: [
          SiteInfo(key: 'a', name: '甲站', api: 'a.py'),
          SiteInfo(key: 'b', name: '乙站', api: 'b.py'),
        ],
      ),
    );
    await store.selectSource('py-empty-site');

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));

    // 原版的话：换一个站点试试。这里不能说「源坏了」，也不能端出乙站的片单
    // 顶在甲站名下。
    expect(find.textContaining('甲站'), findsWidgets);
    expect(find.text('换个站点'), findsOneWidget);
    expect(find.text('乙站片'), findsNothing);
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

  test('字幕偏好、字号与次字幕都写进设置', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    await store.updateSettings(
      store.settings.copyWith(
        subtitlePref: 'zh',
        subtitleSize: 42,
        secondarySubtitle: 'ja',
      ),
    );
    expect(store.settings.subtitlePref, 'zh');
    expect(store.settings.subtitleSize, 42);
    expect(store.settings.secondarySubtitle, 'ja');
  });


  test('记住的轨道选择可以清空', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    await store.saveTrackPrefs('101|线路一', const TrackPrefs(audio: '2'));
    await store.saveTrackPrefs('102|线路二', const TrackPrefs(subtitle: 'no'));
    expect(store.trackPrefCount, 2);
    await store.clearTrackPrefs();
    expect(store.trackPrefCount, 0);
  });


  test('字幕网站配置写进设置并持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    await store.updateSettings(
      store.settings.copyWith(
        subtitleSites: [
          {'name': '测试站', 'url': 'https://example.com/?q={query}'},
        ],
      ),
    );
    expect(store.settings.subtitleSites.single['name'], '测试站');
  });


  test('AI 翻译 Key 只留在本机设置', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    await store.updateSettings(store.settings.copyWith(aiApiKey: 'my-key'));
    expect(store.settings.aiApiKey, 'my-key');
    expect(store.exportBundle()['settings'].containsKey('aiApiKey'), isFalse);
  });


  test('弹幕开关、屏蔽位与弹幕源都写进设置', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    await store.updateSettings(
      store.settings.copyWith(
        danmakuEnabled: false,
        danmakuBlockBottom: true,
        danmakuSources: [
          {'name': '弹弹play', 'appId': '', 'appSecret': ''},
        ],
      ),
    );
    expect(store.settings.danmakuEnabled, isFalse);
    expect(store.settings.danmakuBlockBottom, isTrue);
    expect(store.settings.danmakuSources.single['name'], '弹弹play');
  });

}
