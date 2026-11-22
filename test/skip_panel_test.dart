import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/skip_rule.dart';
import 'package:lai_cui_ba/ui/widgets/skip_panel.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(backgroundColor: Colors.black, body: Center(child: child)),
);

/// The panel is the only place a per-work intro can be set, so these cover what
/// it says and what a tap hands back — not just that it renders.
void main() {
  const global = SkipRule(
    intro: Duration(seconds: 90),
    outro: Duration(seconds: 60),
  );

  testWidgets('跟随全局时说清全局是多少，并且能点出本剧的值', (tester) async {
    SkipOverride? picked;
    await tester.pumpWidget(
      _wrap(
        SkipPanel(
          global: global,
          own: SkipOverride.none,
          effective: global,
          enabled: true,
          onPicked: (o) => picked = o,
        ),
      ),
    );

    expect(find.text('本剧片头片尾'), findsOneWidget);
    expect(find.textContaining('跟随全局'), findsOneWidget);
    expect(find.textContaining('片头 90 秒'), findsOneWidget);

    // 片头一行里点 30，只该覆盖片头。
    await tester.tap(find.widgetWithText(GestureDetector, '30').first);
    await tester.pump();
    expect(picked, const SkipOverride(introMs: 30000));
  });

  testWidgets('片尾那一行的预设改的是片尾', (tester) async {
    SkipOverride? picked;
    await tester.pumpWidget(
      _wrap(
        SkipPanel(
          global: global,
          own: const SkipOverride(introMs: 30000),
          effective: const SkipRule(
            intro: Duration(seconds: 30),
            outro: Duration(seconds: 60),
          ),
          enabled: true,
          onPicked: (o) => picked = o,
        ),
      ),
    );

    // 第二行（片尾）里的「120」。
    final row = find.ancestor(
      of: find.text('片尾'),
      matching: find.byType(Row),
    );
    final chip = find.descendant(of: row.first, matching: find.text('120'));
    await tester.tap(chip);
    await tester.pump();

    expect(picked?.outroMs, 120000);
    expect(picked?.introMs, 30000, reason: '改片尾不该动片头');
  });

  testWidgets('设过本剧覆盖时才出现清除入口', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SkipPanel(
          global: global,
          own: SkipOverride.none,
          effective: global,
          enabled: true,
          onPicked: (_) {},
        ),
      ),
    );
    expect(find.text('清除本剧设置'), findsNothing);

    SkipOverride? picked;
    await tester.pumpWidget(
      _wrap(
        SkipPanel(
          global: global,
          own: const SkipOverride(introMs: 15000),
          effective: const SkipRule(
            intro: Duration(seconds: 15),
            outro: Duration(seconds: 60),
          ),
          enabled: true,
          onPicked: (o) => picked = o,
        ),
      ),
    );
    expect(find.textContaining('本剧单独设置'), findsOneWidget);
    await tester.tap(find.text('清除本剧设置'));
    await tester.pump();
    expect(picked, SkipOverride.none);
  });

  testWidgets('总开关关掉时不给改，并说明原因', (tester) async {
    SkipOverride? picked;
    await tester.pumpWidget(
      _wrap(
        SkipPanel(
          global: SkipRule.none,
          own: SkipOverride.none,
          effective: SkipRule.none,
          enabled: false,
          onPicked: (o) => picked = o,
        ),
      ),
    );

    expect(find.textContaining('已关闭'), findsOneWidget);
    await tester.tap(find.widgetWithText(GestureDetector, '90').first);
    await tester.pump();
    expect(picked, isNull);
  });

  testWidgets('高亮的是实际生效的值', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SkipPanel(
          global: const SkipRule(intro: Duration(seconds: 90)),
          own: const SkipOverride(introMs: 45000),
          effective: const SkipRule(intro: Duration(seconds: 45)),
          enabled: true,
          onPicked: (_) {},
        ),
      ),
    );

    // 45 秒不在预设里：没有哪一枚能冒充"当前值"，状态行必须如实写出来。
    expect(find.textContaining('本剧单独设置'), findsOneWidget);
    expect(find.textContaining('45 秒'), findsOneWidget);
  });
}
