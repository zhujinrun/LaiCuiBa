import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/picture.dart';
import 'package:lai_cui_ba/ui/widgets/picture_panel.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(backgroundColor: Colors.black, body: Center(child: child)),
);

void main() {
  testWidgets('列出六档画面比例，当前档打勾', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PicturePanel(
          mode: AspectMode.fit,
          adjust: PictureAdjust.none,
          onMode: _noopMode,
          onAdjust: _noopAdjust,
        ),
      ),
    );

    expect(find.text('画面比例'), findsOneWidget);
    expect(find.text('画面调节'), findsOneWidget);
    for (final m in AspectMode.values) {
      expect(find.text(m.label), findsOneWidget);
    }
    // 六个勾里只有当前档亮着。
    expect(find.byIcon(Icons.check), findsOneWidget);
    // 五个调节滑块。
    expect(find.text('亮度'), findsOneWidget);
    expect(find.text('对比度'), findsOneWidget);
    expect(find.text('饱和度'), findsOneWidget);
    expect(find.text('色相'), findsOneWidget);
    expect(find.text('伽马'), findsOneWidget);
  });

  testWidgets('点一档比例上报那一档', (tester) async {
    AspectMode? picked;
    await tester.pumpWidget(
      _wrap(
        PicturePanel(
          mode: AspectMode.fit,
          adjust: PictureAdjust.none,
          onMode: (m) => picked = m,
          onAdjust: _noopAdjust,
        ),
      ),
    );

    await tester.tap(find.text('拉伸全屏'));
    expect(picked, AspectMode.stretch);
  });

  testWidgets('拖亮度上报新的调节值，其余不变', (tester) async {
    PictureAdjust? next;
    await tester.pumpWidget(
      _wrap(
        PicturePanel(
          mode: AspectMode.fit,
          adjust: PictureAdjust.none,
          onMode: _noopMode,
          onAdjust: (a) => next = a,
        ),
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
          mode: AspectMode.fit,
          adjust: const PictureAdjust(brightness: 30),
          onMode: _noopMode,
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
      _wrap(
        const PicturePanel(
          mode: AspectMode.fit,
          adjust: PictureAdjust.none,
          onMode: _noopMode,
          onAdjust: _noopAdjust,
        ),
      ),
    );

    expect(find.text('恢复原始画面'), findsNothing);
  });
}

void _noopMode(AspectMode _) {}
void _noopAdjust(PictureAdjust _) {}
