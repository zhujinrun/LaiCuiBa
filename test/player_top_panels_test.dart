import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/ui/widgets/comments_dialog.dart';
import 'package:lai_cui_ba/ui/widgets/kernel_dialog.dart';

Widget _host(VoidCallback onTap) => MaterialApp(
  home: Scaffold(body: Center(child: ElevatedButton(onPressed: onTap, child: const Text('open')))),
);

void main() {
  testWidgets('播放内核面板按原版列出 MPV / ExoPlayer / MDK', (tester) async {
    await tester.pumpWidget(_host(() => showKernelDialog(tester.element(find.byType(Scaffold)))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('播放内核'), findsOneWidget);
    expect(find.text('MPV'), findsOneWidget);
    expect(find.text('兼容格式最广，支持 PGS / ASS 字幕'), findsOneWidget);
    expect(find.text('仅 Android / iOS 可用'), findsOneWidget);
    expect(find.text('libmdk，低开销并支持 FFmpeg 软解'), findsOneWidget);
  });

  testWidgets('评论抽屉只有原版外壳和诚实的空态', (tester) async {
    await tester.pumpWidget(_host(() => showCommentsDialog(tester.element(find.byType(Scaffold)))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('评论'), findsOneWidget);
    expect(find.text('Bangumi'), findsOneWidget);
    expect(find.text('豆瓣'), findsOneWidget);
    expect(find.textContaining('不显示未经核实的内容'), findsOneWidget);
  });
}
