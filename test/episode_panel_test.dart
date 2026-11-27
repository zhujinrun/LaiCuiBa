import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/ui/widgets/episode_panel.dart';

Future<void> _wide(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1040);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('列出每一集，标题写着总集数', (tester) async {
    await _wide(tester);
    await tester.pumpWidget(
      _wrap(
        EpisodePanel(
          episodes: [for (var i = 1; i <= 12; i++) '第$i集'],
          currentIndex: 0,
          onPick: (_) {},
        ),
      ),
    );

    expect(find.text('选集'), findsOneWidget);
    expect(find.text('共 12 集'), findsOneWidget);
    expect(find.text('第1集'), findsOneWidget);
    expect(find.text('第12集'), findsOneWidget);
  });

  testWidgets('点哪一集就报哪一个下标，点正在播的那集不发生任何事', (tester) async {
    await _wide(tester);
    final picked = <int>[];
    await tester.pumpWidget(
      _wrap(
        EpisodePanel(
          episodes: [for (var i = 1; i <= 6; i++) '第$i集'],
          currentIndex: 2,
          onPick: picked.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('episode-chip-2')));
    await tester.pump();
    expect(picked, isEmpty);

    await tester.tap(find.byKey(const ValueKey('episode-chip-4')));
    await tester.pump();
    expect(picked, [4]);
  });

  testWidgets('没有集号的作品用下标兜底，长名字截断而不是撑破格子', (tester) async {
    await _wide(tester);
    await tester.pumpWidget(
      _wrap(
        EpisodePanel(
          episodes: const ['', '第十二集：一个特别特别长的标题'],
          currentIndex: -1,
          onPick: (_) {},
        ),
      ),
    );

    expect(find.text('1'), findsOneWidget);
    // 12 个字截断：多出来的「的标题」不会顶破 64 宽的格子。
    expect(find.text('第十二集：一个特别特别长'), findsOneWidget);
  });

  testWidgets('选集抽屉能搜索并能倒序', (tester) async {
    await _wide(tester);
    await tester.pumpWidget(
      _wrap(
        EpisodePanel(
          episodes: [for (var i = 1; i <= 12; i++) '第$i集'],
          currentIndex: 0,
          onPick: (_) {},
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '第3');
    await tester.pumpAndSettle();
    expect(find.text('第3集'), findsOneWidget);
    expect(find.text('第4集'), findsNothing);

    await tester.tap(find.text('正序'));
    await tester.pumpAndSettle();
    expect(find.text('倒序'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('第12集'), findsOneWidget);
  });
}
