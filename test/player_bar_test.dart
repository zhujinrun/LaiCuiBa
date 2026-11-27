import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/ui/widgets/player_bar.dart';

/// 底栏是原版对齐里最容易悄悄长东西的地方：每加一个功能都想在条上放个按钮。
/// 这几条钉住原版截图里的那一排图标，以及右键进度条的片头片尾入口。
Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);

Future<void> _wide(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1040);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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
  volume: 80,
  onFullScreen: () {},
  onMiniWindow: () {},
);

void main() {
  testWidgets('底栏文字模式保留原版那一排功能名', (tester) async {
    await _wide(tester);
    await tester.pumpWidget(_wrap(_bar()));

    for (final label in [
      '倍速',
      '字幕',
      '弹幕',
      '比例',
      '画面',
      '信息',
      '投屏',
      '选集',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '缺了「$label」');
    }
    expect(find.text('轨道'), findsNothing);
    expect(find.text('02:25 / 49:00'), findsOneWidget);
  });

  testWidgets('原版没有的「片头」不在底栏上', (tester) async {
    await _wide(tester);
    await tester.pumpWidget(_wrap(_bar()));
    expect(find.textContaining('片头'), findsNothing);
  });

  testWidgets('图标模式还带音量滑杆、画中画和全屏', (tester) async {
    await _wide(tester);
    await tester.pumpWidget(_wrap(_bar(iconMode: true)));

    for (final label in [
      '倍速',
      '字幕',
      '弹幕',
      '比例',
      '画面',
      '信息',
      '投屏',
      '选集',
    ]) {
      expect(find.text(label), findsNothing, reason: '图标模式不该再写「$label」');
    }
    for (final icon in [
      Icons.speed,
      Icons.closed_caption,
      Icons.chat_bubble_outline,
      Icons.aspect_ratio,
      Icons.tune,
      Icons.info_outline,
      Icons.cast,
      Icons.list,
      Icons.picture_in_picture_alt,
      Icons.fullscreen,
      Icons.volume_up,
    ]) {
      expect(find.byIcon(icon), findsOneWidget, reason: '缺了图标 $icon');
    }
    // 进度条 + 原版底栏的音量滑杆。
    expect(find.byType(Slider), findsNWidgets(2));
  });

  testWidgets('字幕 / 比例 / 画面 是三个独立出口', (tester) async {
    await _wide(tester);
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
    await _wide(tester);
    var opened = 0;
    await tester.pumpWidget(_wrap(_bar(onSkipPanel: () => opened++)));

    await tester.tap(find.byType(Slider).first, buttons: kSecondaryButton);
    expect(opened, 1);
  });

  testWidgets('只有一集时不摆「选集」', (tester) async {
    await _wide(tester);
    await tester.pumpWidget(_wrap(_bar(episodeCount: 1)));
    expect(find.text('选集'), findsNothing);
  });
}
