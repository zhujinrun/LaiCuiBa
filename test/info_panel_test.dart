import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/ui/widgets/info_panel.dart';

void main() {
  testWidgets('信息显示面板按原版列出七行与五个位置', (tester) async {
    Map<String, String> saved = {};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InfoPanel(
            positions: const {},
            onChanged: (v) => saved = v,
            miniProgress: false,
            onMiniProgress: (_) {},
          ),
        ),
      ),
    );

    for (final label in [
      '电量',
      '当前时间',
      '视频帧率',
      '分辨率',
      '播放进度',
      '网速',
      '迷你进度条',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '缺了「$label」');
    }
    for (final spot in ['关', '左上', '右上', '左下', '右下']) {
      expect(find.text(spot), findsWidgets);
    }

    // 第一行的「左上」把分辨率之外的项写进设置。
    await tester.tap(find.text('左上').first);
    expect(saved['battery'], 'topLeft');
  });
}
