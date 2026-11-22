import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/track_choice.dart';
import 'package:lai_cui_ba/ui/widgets/track_panel.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(backgroundColor: Colors.black, body: Center(child: child)),
);

void main() {
  testWidgets('a stream with nothing to switch says so instead of faking options', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const TrackPanel(
          choices: TrackChoices(
            audio: [TrackOption(id: '1', language: 'zh')],
          ),
        ),
      ),
    );

    expect(find.text('这条流没有可切换的轨道'), findsOneWidget);
    expect(find.text('画质'), findsNothing);
    expect(find.text('字幕'), findsNothing);
  });

  testWidgets('groups appear only when there is a real choice', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TrackPanel(
          choices: const TrackChoices(
            video: [
              TrackOption(id: '1', width: 3840, height: 2160),
              TrackOption(id: '2', width: 1280, height: 720),
            ],
            audio: [
              TrackOption(id: '3', title: '国语'),
              TrackOption(id: '4', title: '粤语'),
            ],
            subtitle: [TrackOption(id: '5', language: 'zh')],
            videoId: '1',
            audioId: '4',
            subtitleId: '5',
          ),
          lines: const ['线路一', '线路二'],
          lineIndex: 1,
          onLine: (_) {},
          onVideo: (_) {},
          onAudio: (_) {},
          onSubtitle: (_) {},
        ),
      ),
    );

    expect(find.text('线路'), findsOneWidget);
    expect(find.text('画质'), findsOneWidget);
    expect(find.text('声音'), findsOneWidget);
    expect(find.text('字幕'), findsOneWidget);
    expect(find.text('线路二'), findsOneWidget);
    expect(find.text('国语'), findsOneWidget);
    expect(find.text('粤语'), findsOneWidget);
    // 字幕组永远带一个「关闭」，因为它是一个有效的选择。
    expect(find.text('关闭'), findsOneWidget);
  });

  testWidgets('tapping a row reports the picked track, not the label', (tester) async {
    TrackOption? pickedAudio;
    TrackOption? pickedSub;
    int? pickedLine;

    await tester.pumpWidget(
      _wrap(
        TrackPanel(
          choices: const TrackChoices(
            audio: [
              TrackOption(id: '3', title: '国语'),
              TrackOption(id: '4', title: '粤语'),
            ],
            subtitle: [TrackOption(id: '5', language: 'zh')],
            audioId: '3',
            subtitleId: '5',
          ),
          lines: const ['线路一', '线路二'],
          lineIndex: 0,
          onLine: (i) => pickedLine = i,
          onAudio: (t) => pickedAudio = t,
          onSubtitle: (t) => pickedSub = t,
        ),
      ),
    );

    await tester.tap(find.text('粤语'));
    expect(pickedAudio?.id, '4');

    await tester.tap(find.text('线路二'));
    expect(pickedLine, 1);

    await tester.tap(find.text('关闭'));
    expect(pickedSub?.id, 'no');
  });

  testWidgets('本地字幕入口在没有字幕轨时也开着', (tester) async {
    // 一条内嵌字幕都没有的片子，正是最需要「选个本地字幕」的时候。
    await tester.pumpWidget(
      _wrap(
        TrackPanel(
          choices: const TrackChoices(),
          onPickSubtitleFile: () {},
        ),
      ),
    );

    expect(find.text('这条流没有可切换的轨道'), findsNothing);
    expect(find.text('字幕'), findsOneWidget);
    expect(find.text('选择本地字幕文件…'), findsOneWidget);
    // 没挂字幕时不该有「取消外挂字幕」这一行。
    expect(find.text('不再使用外挂字幕'), findsNothing);
  });

  testWidgets('挂上字幕后面板显示它是哪一份，并给一个取消入口', (tester) async {
    var cleared = 0;
    await tester.pumpWidget(
      _wrap(
        TrackPanel(
          choices: const TrackChoices(
            subtitle: [TrackOption(id: '2', language: 'zh')],
            subtitleId: '2',
          ),
          externalSubtitleLabel: '01.ass',
          onPickSubtitleFile: () {},
          onClearSubtitleFile: () => cleared++,
        ),
      ),
    );

    expect(find.text('外挂：01.ass'), findsOneWidget);
    await tester.tap(find.text('不再使用外挂字幕'));
    expect(cleared, 1);
  });

  testWidgets('a single line is not offered as a choice', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TrackPanel(
          choices: const TrackChoices(
            audio: [
              TrackOption(id: '1', title: '国语'),
              TrackOption(id: '2', title: '粤语'),
            ],
          ),
          lines: const ['唯一线路'],
          lineIndex: 0,
          onLine: (_) {},
        ),
      ),
    );

    expect(find.text('线路'), findsNothing);
    expect(find.text('唯一线路'), findsNothing);
    expect(find.text('声音'), findsOneWidget);
  });
}
