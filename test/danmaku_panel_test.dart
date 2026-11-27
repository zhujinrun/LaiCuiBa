import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/ui/widgets/danmaku_panel.dart';

void main() {
  testWidgets('弹幕图标打开的是设置面板，不是一键开关', (tester) async {
    var toggled = 0;
    var top = false;
    var bottom = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DanmakuPanel(
              on: false,
              onToggle: () => toggled++,
              blockTop: false,
              onBlockTop: (v) => top = v,
              blockBottom: false,
              onBlockBottom: (v) => bottom = v,
              opacity: 0.8,
              onOpacity: (_) {},
              fontSize: 16,
              onFontSize: (_) {},
              hasSource: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('显示弹幕'), findsOneWidget);
    expect(find.textContaining('未配置弹幕源'), findsOneWidget);
    expect(find.text('屏蔽顶部弹幕'), findsOneWidget);
    expect(find.text('屏蔽底部弹幕'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    expect(toggled, 1);
    await tester.tap(find.byType(Switch).at(1));
    expect(top, isTrue);
    await tester.tap(find.byType(Switch).at(2));
    expect(bottom, isTrue);
  });
}
