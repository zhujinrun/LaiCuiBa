import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/ui/widgets/playback_error_overlay.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 1280, height: 720, child: child)),
);

void main() {
  testWidgets('打不开时摆出人话、原话和重试', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var retried = 0;
    await tester.pumpWidget(
      _wrap(
        PlaybackErrorOverlay(
          raw: 'mpv: Could not create window',
          onRetry: () => retried++,
        ),
      ),
    );

    expect(find.text('这一集打不开'), findsOneWidget);
    // 一句能动手的话，加一行原始信息给能看懂的人。
    expect(
      find.text('无法创建播放画面：这台机器（或远程桌面）不支持当前的渲染方式'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('playback-error-raw')),
      findsOneWidget,
    );
    // 没有别的线路就不摆一个按不动的按钮，也不再摆「下一集」。
    expect(find.text('切换线路'), findsNothing);
    expect(find.text('下一集'), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets('重试中按钮不重复触发，有别的线路时给切换出口', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var retried = 0;
    var switched = 0;
    await tester.pumpWidget(
      _wrap(
        PlaybackErrorOverlay(
          raw: '404 Not Found',
          retrying: true,
          onRetry: () => retried++,
          onSwitchLine: () => switched++,
        ),
      ),
    );

    expect(find.text('正在重试…'), findsOneWidget);
    await tester.tap(find.text('正在重试…'));
    await tester.pump();
    expect(retried, 0);

    expect(find.text('下一集'), findsNothing);
    await tester.tap(find.text('切换线路'));
    await tester.pump();
    expect(switched, 1);
  });
}
