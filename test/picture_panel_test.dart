import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/picture.dart';
import 'package:lai_cui_ba/ui/widgets/picture_panel.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: child),
  ),
);

void main() {
  testWidgets('画面面板只剩五个调节量，比例不在里面了', (tester) async {
    await tester.pumpWidget(
      _wrap(const PicturePanel(adjust: PictureAdjust.none, onAdjust: _noop)),
    );

    expect(find.text('画面调节'), findsOneWidget);
    expect(find.text('亮度'), findsOneWidget);
    expect(find.text('对比度'), findsOneWidget);
    expect(find.text('饱和度'), findsOneWidget);
    expect(find.text('色相'), findsOneWidget);
    expect(find.text('伽马'), findsOneWidget);
    // 比例已经拆到「比例」按钮下，这里不该再出现一遍。
    expect(find.text('画面比例'), findsNothing);
    for (final m in AspectMode.values) {
      expect(find.text(m.label), findsNothing);
    }
  });

  testWidgets('拖亮度上报新的调节值，其余不变', (tester) async {
    PictureAdjust? next;
    await tester.pumpWidget(
      _wrap(
        PicturePanel(adjust: PictureAdjust.none, onAdjust: (a) => next = a),
      ),
    );

    // 五个 Slider，第一个是亮度。
    final slider = find.byType(Slider).first;
    await tester.drag(slider, const Offset(50, 0));
    await tester.pump();

    expect(next, isNotNull);
    expect(next!.brightness, isNot(0));
    expect(next!.contrast, 0);
    expect(next!.saturation, 0);
  });

  testWidgets('非中性调节时给「恢复原始画面」入口', (tester) async {
    var reset = 0;
    await tester.pumpWidget(
      _wrap(
        PicturePanel(
          adjust: const PictureAdjust(brightness: 30),
          onAdjust: (a) {
            if (a.isNeutral) reset++;
          },
        ),
      ),
    );

    expect(find.text('恢复原始画面'), findsOneWidget);
    await tester.ensureVisible(find.text('恢复原始画面'));
    await tester.pump();
    await tester.tap(find.text('恢复原始画面'));
    expect(reset, 1);
  });

  testWidgets('中性调节时不显示恢复入口', (tester) async {
    await tester.pumpWidget(
      _wrap(const PicturePanel(adjust: PictureAdjust.none, onAdjust: _noop)),
    );

    expect(find.text('恢复原始画面'), findsNothing);
  });

  testWidgets('画面面板还给出全屏、小窗和截图三个真出口', (tester) async {
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var full = 0;
    var mini = 0;
    var shot = 0;
    await tester.pumpWidget(
      _wrap(
        PicturePanel(
          adjust: PictureAdjust.none,
          onAdjust: _noop,
          onFullScreen: () => full++,
          onMiniWindow: () => mini++,
          onScreenshot: () => shot++,
        ),
      ),
    );

    expect(find.text('全屏（F）'), findsOneWidget);
    expect(find.text('小窗播放'), findsOneWidget);
    expect(find.text('截图'), findsOneWidget);
    await tester.tap(find.text('全屏（F）'));
    await tester.tap(find.text('小窗播放'));
    await tester.tap(find.text('截图'));
    await tester.pump();
    expect(full, 1);
    expect(mini, 1);
    expect(shot, 1);
  });
}

void _noop(PictureAdjust _) {}
