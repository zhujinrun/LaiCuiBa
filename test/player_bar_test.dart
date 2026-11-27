import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/ui/widgets/player_bar.dart';

/// 底栏是原版对齐里最容易悄悄长东西的地方：每加一个功能都想在条上放个按钮。
/// 这几条测的不是像素，而是「条上到底有哪几个东西」。
Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);

PlayerBar _bar({
  VoidCallback? onSubtitle,
  VoidCallback? onAspect,
  VoidCallback? onPicture,
  VoidCallback? onTracks,
  VoidCallback? onSkipPanel,
  int episodeCount = 3,
  bool iconMode = false,
}) => PlayerBar(
  playing: true,
  buffering: false,
  position: const Duration(minutes: 2, seconds: 25),
  duration: const Duration(minutes: 49),
  rate: 1.0,
  visible: true,
  onTogglePlay: () {},
  onSeekStart: () {},
  onSeekEnd: () {},
  onSeekChanged: (_) {},
  onRatePanel: () {},
  rateOpen: false,
  onSubtitle: onSubtitle ?? () {},
  subtitleOpen: false,
  onDanmaku: () {},
  danmakuOn: false,
  danmakuAsking: false,
  onTracks: onTracks,
  onAspect: onAspect ?? () {},
  aspectOpen: false,
  onPicture: onPicture ?? () {},
  pictureOpen: false,
  onInfo: () {},
  infoOpen: false,
  onEpisodes: () {},
  episodesOpen: false,
  episodeCount: episodeCount,
  onSkipPanel: onSkipPanel ?? () {},
  iconMode: iconMode,
);

void main() {
  testWidgets('底栏的按钮就是原版那一排：倍速 字幕 弹幕 比例 画面 信息 选集', (tester) async {
    await tester.pumpWidget(_wrap(_bar()));

    for (final label in ['倍速', '字幕', '弹幕', '比例', '画面', '信息', '投屏', '选集']) {
      expect(find.text(label), findsOneWidget, reason: '缺了「$label」');
    }
    // 原版底栏没有自创的「轨道」，那一排是完整文字。
    expect(find.text('轨道'), findsNothing);
  });

  testWidgets('原版没有的「片头」不在底栏上', (tester) async {
    await tester.pumpWidget(_wrap(_bar()));
    expect(find.textContaining('片头'), findsNothing);
  });

  testWidgets('条上只有一根滑杆（进度），没有音量滑杆', (tester) async {
    await tester.pumpWidget(_wrap(_bar()));
    expect(find.byType(Slider), findsOneWidget);
    // 音量改为在画面上滚轮调（player_page 的 _nudgeVolume），底栏不再有它。
    expect(find.byIcon(Icons.volume_up), findsNothing);
    expect(find.byIcon(Icons.volume_off), findsNothing);
  });

  testWidgets('字幕 / 比例 / 画面 是三个独立出口，不再挤在一个「轨道」里', (tester) async {
    var subtitle = 0;
    var aspect = 0;
    var picture = 0;
    await tester.pumpWidget(
      _wrap(
        _bar(
          onSubtitle: () => subtitle++,
          onAspect: () => aspect++,
          onPicture: () => picture++,
        ),
      ),
    );

    await tester.tap(find.text('字幕'));
    expect(subtitle, 1);
    expect(aspect, 0);
    expect(picture, 0);

    await tester.tap(find.text('比例'));
    expect(aspect, 1);
    expect(picture, 0);

    await tester.tap(find.text('画面'));
    expect(picture, 1);
  });

  testWidgets('右键进度条打开本剧片头片尾', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_wrap(_bar(onSkipPanel: () => opened++)));

    await tester.tap(find.byType(Slider), buttons: kSecondaryButton);
    expect(opened, 1);
  });

  testWidgets('只有一集时不摆「选集」', (tester) async {
    await tester.pumpWidget(_wrap(_bar(episodeCount: 1)));
    expect(find.text('选集'), findsNothing);
  });

  testWidgets('操作按钮可以换成图标，功能一个不少', (tester) async {
    await tester.pumpWidget(_wrap(_bar(iconMode: true)));
    for (final label in ['倍速', '字幕', '弹幕', '比例', '画面', '信息', '投屏', '选集']) {
      expect(find.text(label), findsNothing, reason: '图标模式不该再写「$label」');
    }
    expect(find.byIcon(Icons.speed), findsOneWidget);
    expect(find.byIcon(Icons.closed_caption), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(find.byIcon(Icons.aspect_ratio), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.byIcon(Icons.cast), findsOneWidget);
    expect(find.byIcon(Icons.list), findsOneWidget);
  });
}
