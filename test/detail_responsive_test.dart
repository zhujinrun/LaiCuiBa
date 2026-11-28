import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/core/store_scope.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/ui/pages/detail_page.dart';

/// 详情页在窄窗口下不能出现 RenderFlex 溢出（用户缩小首页宽度后进入详情
/// 看到的黄黑条纹）；操作按钮要像选集 chip 一样保持内容宽度、按需换行；
/// 演员阵容要像选集一样自适应换行，长名单不能被横向 rail 截断。
void main() {
  MediaItem makeItem() => MediaItem(
        id: 'detail-responsive',
        title: '谷雨',
        posterSeed: 1,
        latest: '第30集',
        year: 2026,
        area: '中国大陆',
        overview: '1994年春江市税务局稽查员欧阳旭与刑警严平安'
            '寻妻的周海洋三人因一起假发票案相识于微时，携手屡破税案。',
        categories: const ['剧情', '悬疑', '犯罪'],
        actors: List.generate(24, (i) => '演员${i + 1}'),
        episodes: List.generate(30, (i) => '第${i + 1}集'),
      );

  Future<AppStore> makeStore() async {
    SharedPreferences.setMockInitialValues({});
    return AppStore.load();
  }

  Future<void> pumpDetail(WidgetTester tester, double width, MediaItem item) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: StoreScope(store: await makeStore(), child: DetailPage(item: item)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  for (final width in [1100.0, 1000.0, 900.0, 800.0, 700.0]) {
    testWidgets('详情页在 ${width.toInt()}px 宽时不溢出', (tester) async {
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (details) {
        final message = details.exception.toString();
        if (message.contains('overflowed')) {
          overflows.add(message);
        } else {
          prev?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = prev);

      await pumpDetail(tester, width, makeItem());

      expect(overflows, isEmpty, reason: '宽度 $width 不应出现 RenderFlex 溢出');
    });
  }

  testWidgets('操作按钮保持内容宽度，宽屏一行、窄屏换行', (tester) async {
    Size actionSize(double width) {
      final el = find.byWidgetPredicate(
        (w) => w is Wrap && w.spacing == 13 && w.runSpacing == 13,
      ).evaluate().single;
      return (el.renderObject as RenderBox).size;
    }

    List<Size> pillSizes() {
      final el = find.byWidgetPredicate(
        (w) => w is Wrap && w.spacing == 13 && w.runSpacing == 13,
      ).evaluate().single;
      final sizes = <Size>[];
      (el.renderObject as RenderBox).visitChildren((c) {
        if (c is RenderBox) sizes.add(c.size);
      });
      return sizes;
    }

    // 宽屏：6 个按钮一行，高度就是一个 pill 的 42。
    await pumpDetail(tester, 1840, makeItem());
    expect(actionSize(1840).height, 42);
    final wide = pillSizes();
    expect(wide, hasLength(6));
    // 每个 pill 按内容宽度，而不是被 Wrap 撑满整行。
    expect(wide.every((s) => s.width < 200), isTrue,
        reason: 'pill 应保持内容宽度，实际 ${wide.map((s) => s.width).toList()}');
    // 首个「继续 第01集」最宽，其余在 90~120 之间。
    expect(wide.first.width, greaterThan(wide.last.width));

    // 窄屏：同样的按钮内容宽度不变，但换成多行。
    final wideWidths = wide.map((s) => s.width).toList();
    final narrow = pillSizes();
    expect(narrow.map((s) => s.width).toList(), wideWidths,
        reason: '按钮宽度与窗口无关，保持原有宽度');
  });

  testWidgets('窄屏操作按钮确实换行、hero 随之增高', (tester) async {
    await pumpDetail(tester, 700, makeItem());
    final action = find.byWidgetPredicate(
      (w) => w is Wrap && w.spacing == 13 && w.runSpacing == 13,
    ).evaluate().single;
    expect((action.renderObject as RenderBox).size.height, greaterThan(42),
        reason: '700px 下按钮应换成多行');

    final heroPadding = find.byWidgetPredicate(
      (w) => w is Padding &&
          w.padding == const EdgeInsets.fromLTRB(40, 35, 40, 45),
    ).evaluate().single;
    expect((heroPadding.renderObject as RenderBox).size.height, greaterThan(386),
        reason: '按钮换行后 hero 应增高而不是裁切');
  });

  testWidgets('宽屏 hero 仍保持原版 386 高度', (tester) async {
    await pumpDetail(tester, 1840, makeItem());
    final heroPadding = find.byWidgetPredicate(
      (w) => w is Padding &&
          w.padding == const EdgeInsets.fromLTRB(40, 35, 40, 45),
    ).evaluate().single;
    expect((heroPadding.renderObject as RenderBox).size.height, 386);
  });

  testWidgets('演员阵容用自适应 Wrap，24 个演员全部渲染', (tester) async {
    await pumpDetail(tester, 1000, makeItem());
    // 不再是固定横向 ListView。
    expect(find.byType(ListView), findsNothing,
        reason: '演员阵容不应再用横向 ListView 截断');
    final castWrap = find.byWidgetPredicate(
      (w) => w is Wrap && w.spacing == 18 && w.runSpacing == 22,
    );
    expect(castWrap, findsOneWidget);
    expect(castWrap.evaluate().single.widget as Wrap,
        isA<Wrap>().having((w) => w.children.length, 'children', 24));

    for (var i = 1; i <= 24; i++) {
      expect(find.text('演员$i'), findsOneWidget);
    }
  });

  testWidgets('窄屏演员阵容换成多行', (tester) async {
    double castHeight(double width) {
      final el = find.byWidgetPredicate(
        (w) => w is Wrap && w.spacing == 18 && w.runSpacing == 22,
      ).evaluate().single;
      return (el.renderObject as RenderBox).size.height;
    }

    await pumpDetail(tester, 1840, makeItem());
    final wide = castHeight(1840);
    // 1840 下 24 人排 2 行（98*2 + 22 = 218）。
    expect(wide, 218);

    // WidgetsBinding 复用，重新 pump 到窄屏。
    tester.view.physicalSize = const Size(700, 900);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(castHeight(700), greaterThan(wide), reason: '窄屏演员应换成更多行');
  });

  testWidgets('电影只有几个版本时选集 chip 不被拉伸到半屏', (tester) async {
    const movie = MediaItem(
      id: 'movie',
      title: '谷雨',
      posterSeed: 1,
      episodes: ['TC国语', '枪版'],
    );
    await pumpDetail(tester, 1840, movie);

    final chips = <Size>[];
    for (final el in find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.maxHeight == 44,
    ).evaluate()) {
      chips.add((el.renderObject as RenderBox).size);
    }
    expect(chips, hasLength(2), reason: '电影应渲染 2 个版本 chip');
    for (final size in chips) {
      expect(size.width, 92, reason: '短集名按最小宽度 92px，不能被拉伸到半屏');
    }
  });
}
