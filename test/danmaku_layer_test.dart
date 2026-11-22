import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lai_cui_ba/services/danmaku/danmaku_api.dart';
import 'package:lai_cui_ba/ui/widgets/danmaku_layer.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(width: 800, height: 450, child: child),
        ),
      ),
    );

void main() {
  const comment = DanmakuComment(
    timeMs: 1000,
    text: '弹幕本体',
    color: 0xFFFFFF,
  );

  testWidgets('paints without throwing once a comment is on screen', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const DanmakuLayer(
      comments: [comment],
      position: Duration(milliseconds: 1200),
      playing: false,
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('an empty list renders nothing at all', (tester) async {
    await tester.pumpWidget(_host(const DanmakuLayer(
      comments: [],
      position: Duration.zero,
    )));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(DanmakuLayer),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ticking while playing does not throw and can be disposed', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const DanmakuLayer(
      comments: [comment],
      position: Duration(milliseconds: 900),
      playing: true,
    )));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    // 换成一个空表：层要能在播放中途安全地清空。
    await tester.pumpWidget(_host(const DanmakuLayer(
      comments: [],
      position: Duration(milliseconds: 1500),
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocked zones still render the remaining ones', (tester) async {
    await tester.pumpWidget(_host(const DanmakuLayer(
      comments: [
        comment,
        DanmakuComment(timeMs: 1000, text: '顶部', mode: DanmakuComment.top),
      ],
      position: Duration(milliseconds: 1200),
      playing: false,
      blockTop: true,
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
