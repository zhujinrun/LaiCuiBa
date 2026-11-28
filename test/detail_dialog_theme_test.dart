import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/core/theme.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/ui/widgets/comments_dialog.dart';
import 'package:lai_cui_ba/ui/widgets/detail_action_dialogs.dart';

/// 详情页的弹框与页面同属浅色主题。之前它们硬编码了近黑背景，正文却用
/// 浅色主题的深灰文字，黑底深字几乎读不出来。回归断言背景取自 Theme。
void main() {
  Future<void> openDialog(
    WidgetTester tester,
    void Function(BuildContext context) open,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBclTheme(),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  void expectThemedSurface(WidgetTester tester) {
    final finder = find.byWidgetPredicate((w) => w is Dialog);
    expect(finder, findsOneWidget, reason: '应打开一个弹框');
    final dialog = tester.widget<Dialog>(finder);
    expect(dialog.backgroundColor, isNull,
        reason: '弹框背景应跟随主题，不能硬编码近黑色');
    final theme = Theme.of(tester.element(finder));
    expect(theme.colorScheme.surface, LcbColors.surface);
    expect(theme.colorScheme.surface.computeLuminance(), greaterThan(0.5),
        reason: '默认主题是浅色，弹框底也应是浅色');
  }

  testWidgets('换平台弹框跟随浅色主题', (tester) async {
    await openDialog(tester, (context) => showPlatformDialog(context, '尚公主'));
    expectThemedSurface(tester);
    expect(find.textContaining('没有可用的跨源搜索结果'), findsOneWidget);
  });

  testWidgets('下载弹框跟随浅色主题', (tester) async {
    await openDialog(
      tester,
      (context) => showDownloadDialog(context, const ['第1集']),
    );
    expectThemedSurface(tester);
    expect(find.text('1. 第1集'), findsOneWidget);
  });

  testWidgets('追更弹框跟随浅色主题', (tester) async {
    await openDialog(tester, (context) => showFollowDialog(context, '尚公主'));
    expectThemedSurface(tester);
  });

  testWidgets('收藏到弹框跟随浅色主题', (tester) async {
    await openDialog(
      tester,
      (context) => showFavoriteFolderDialog(
        context,
        const [FavoriteFolder(id: 'f1', name: '好看的电影')],
      ),
    );
    expectThemedSurface(tester);
    expect(find.text('好看的电影'), findsOneWidget);
  });

  testWidgets('评论弹框的文字与填充在浅色主题下可读', (tester) async {
    await openDialog(tester, showCommentsDialog);
    expectThemedSurface(tester);

    final title = tester.widget<Text>(find.text('评论'));
    expect(title.style?.color, LcbColors.text,
        reason: '标题不能是白字，否则在浅色弹框上看不见');
    final titleLarge = Theme.of(tester.element(find.byType(Dialog)))
        .textTheme.titleLarge!;
    expect(title.style?.fontSize, titleLarge.fontSize,
        reason: '评论标题应和其他详情页弹框的 AlertDialog 标题一样大');
    expect(title.style?.fontWeight, titleLarge.fontWeight);

    final hintBox = find.ancestor(
      of: find.textContaining('查找作品'),
      matching: find.byType(Container),
    ).first;
    final decoration = tester.widget<Container>(hintBox).decoration
        as BoxDecoration;
    expect(decoration.color, LcbColors.searchFill,
        reason: '查找提示的底色应是浅灰，而不是原黑底上的半透明白');
  });
}
