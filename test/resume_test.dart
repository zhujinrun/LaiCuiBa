import 'dart:ui' show Size;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart'
    show MaterialApp, Scaffold, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/core/detail_nav.dart';
import 'package:lai_cui_ba/core/nav.dart';
import 'package:lai_cui_ba/core/store_scope.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/ui/pages/common_pages.dart';
import 'package:lai_cui_ba/ui/pages/home_page.dart';

/// 「接着看」这条路：卡片上写着第39集，点进去就得是第39集。
///
/// 三处以前各说各话：继续观看卡片的 id 是 `源|站点|vodId` 这种复合串（拿它
/// 去问详情必然空手而归），点进去落在第1集；历史行右边的圆钮 onTap 是空的；
/// 首页大图的播放一律从第1集开始，哪怕历史里记着第39集。
void main() {
  setUpAll(() => AppStore.seedSampleUserData = true);

  Future<AppStore> seededStore() async {
    SharedPreferences.setMockInitialValues({});
    return AppStore.load();
  }

  testWidgets('继续观看卡片打开它记着的那一集', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await seededStore();
    MediaItem? opened;
    int? openedAt;

    await tester.pumpWidget(
      MaterialApp(
        home: StoreScope(
          store: store,
          child: LcbDetailScope(
            open: (item, {int? episodeIndex}) {
              opened = item;
              openedAt = episodeIndex;
            },
            child: const HomePage(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('继续观看'), findsOneWidget);
    await tester.tap(find.text('尚公主').first);
    await tester.pump();

    // 第39集是示例历史的记录（episodeIndex 38）。
    expect(openedAt, 38);
    // 详情页拿到的必须是源自己的 vod id，不能是 history 的复合 key。
    expect(opened?.id, '575857');
    expect(opened?.siteKey, 'nodejs_jianpian');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('历史行右边的圆钮真的接着放那一集', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await seededStore();
    MediaItem? played;
    int? playedAt;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoreScope(
            store: store,
            child: LcbPlayScope(
              play: (item, {int? episodeIndex}) {
                played = item;
                playedAt = episodeIndex;
              },
              child: const HistoryPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 以前这个钮的 onTap 是 `() {}`，按下去一点反应都没有。
    await tester.tap(find.byIcon(CupertinoIcons.play_fill).first);
    await tester.pump();

    expect(playedAt, 38);
    expect(played?.id, '575857');
    expect(played?.siteKey, 'nodejs_jianpian');
  });

  group('AppStore.startEpisodeFor', () {
    test('有历史就回到历史那一集，没有历史从第1集开始', () async {
      final store = await seededStore();
      const series = MediaItem(
        id: '575857',
        title: '尚公主',
        siteKey: 'nodejs_jianpian',
        episodes: ['第1集', '第2集', '第39集', '第40集'],
      );

      // 历史里是第39集（index 38），但这份记录只有 4 集 —— 集的编号在两次
      // 访问之间变了，就退到最后，而不是越界交给播放器。
      expect(store.startEpisodeFor(series), 3);

      const stranger = MediaItem(
        id: 'unknown',
        title: '没看过',
        episodes: ['第1集', '第2集'],
      );
      expect(store.startEpisodeFor(stranger), 0);
    });

    test('历史按 vod id 认，不靠片名', () async {
      final store = await seededStore();
      // 同名不同 id：不是同一部，不该把别人的续播点搬过来。
      const sameName = MediaItem(id: 'other', title: '尚公主');
      expect(store.historyFor(sameName), isNull);

      const real = MediaItem(
        id: '575857',
        title: '尚公主（换了名字）',
        siteKey: 'nodejs_jianpian',
      );
      expect(store.historyFor(real)?.key, contains('575857'));

      // 同一个 vod id 但在别的站点：不是同一部。
      const otherSite = MediaItem(
        id: '575857',
        title: '尚公主',
        siteKey: 'another_site',
      );
      expect(store.historyFor(otherSite), isNull);
    });

    test('没有 vod id 的老记录只能按片名兜底', () async {
      final store = await seededStore();
      await store.putHistory(
        const HistoryEntry(
          key: 'old-source|s1|',
          sourceId: 'old-source',
          title: '老片',
          poster: '',
          episode: '第2集',
          episodeIndex: 1,
          positionMs: 1000,
          durationMs: 10000,
          updatedAt: 0,
          siteKey: 's1',
        ),
      );
      expect(
        store
            .historyFor(const MediaItem(id: 'whatever', title: '老片'))
            ?.episodeIndex,
        1,
      );
      expect(
        store.historyFor(const MediaItem(id: 'whatever', title: '别的片')),
        isNull,
      );
    });
  });

  test('continueWatching 带出可用的 vod id 与集数', () async {
    final store = await seededStore();
    final row = store.continueWatching.single;
    expect(row.media.id, '575857');
    expect(row.media.siteKey, 'nodejs_jianpian');
    expect(row.episodeIndex, 38);
    expect(row.episodeLabel, '第39集');
  });
}
