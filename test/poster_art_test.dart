import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/core/theme.dart';
import 'package:lai_cui_ba/ui/widgets/poster_art.dart';

/// 没有封面时画什么。
///
/// 卡片上必须是原版那块中性灰 + 小胶片图标 —— 之前这里画的是按 seed 生成的
/// 彩色渐变，看起来像一张「有设计感的假封面」，与「界面只显示真实数据」相悖。
/// hero 的模糊背景是例外：它是标题背后的色层，不是封面替身。
void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: SizedBox(width: 196, height: 294, child: child))),
  );

  testWidgets('a missing cover is the neutral card with a film glyph', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const PosterArt()));

    expect(find.byIcon(CupertinoIcons.film), findsOneWidget);
    final box = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(PosterArt),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(box.color, LcbColors.searchFill);
  });

  testWidgets('the hero backdrop keeps the colour wash, not the grey card', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const PosterArt(plain: false)));

    expect(find.byIcon(CupertinoIcons.film), findsNothing);
    expect(find.byType(DecoratedBox), findsWidgets);
  });
}
