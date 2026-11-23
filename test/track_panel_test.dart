import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/track_choice.dart';
import 'package:lai_cui_ba/ui/widgets/track_panel.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: child),
  ),
);

void main() {
  testWidgets(
    'a stream with nothing to switch says so instead of faking options',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TrackPanel(
            choices: TrackChoices(
              audio: [TrackOption(id: '1', language: 'zh')],
            ),
          ),
        ),
      );

      expect(find.text('这条流没有可切换的线路或音轨'), findsOneWidget);
      expect(find.text('画质'), findsNothing);
      expect(find.text('字幕'), findsNothing);
    },
  );

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
            videoId: '1',
            audioId: '4',
          ),
          lines: const ['线路一', '线路二'],
          lineIndex: 1,
          onLine: (_) {},
          onVideo: (_) {},
          onAudio: (_) {},
        ),
      ),
    );

    expect(find.text('线路'), findsOneWidget);
    expect(find.text('画质'), findsOneWidget);
    expect(find.text('声音'), findsOneWidget);
    expect(find.text('线路二'), findsOneWidget);
    expect(find.text('国语'), findsOneWidget);
    expect(find.text('粤语'), findsOneWidget);
    // 字幕已经拆到自己的按钮下面，这里不再出现。
    expect(find.text('字幕'), findsNothing);
    expect(find.text('关闭'), findsNothing);
  });

  testWidgets('tapping a row reports the picked track, not the label', (
    tester,
  ) async {
    TrackOption? pickedAudio;
    int? pickedLine;

    await tester.pumpWidget(
      _wrap(
        TrackPanel(
          choices: const TrackChoices(
            audio: [
              TrackOption(id: '3', title: '国语'),
              TrackOption(id: '4', title: '粤语'),
            ],
            audioId: '3',
          ),
          lines: const ['线路一', '线路二'],
          lineIndex: 0,
          onLine: (i) => pickedLine = i,
          onAudio: (t) => pickedAudio = t,
        ),
      ),
    );

    await tester.tap(find.text('粤语'));
    expect(pickedAudio?.id, '4');

    await tester.tap(find.text('线路二'));
    expect(pickedLine, 1);
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

  group('底栏要不要摆「轨道」按钮', () {
    test('一条流一条音轨、一条线路时不摆——底栏就和原版一样', () {
      expect(
        TrackPanel.worthShowing(
          choices: const TrackChoices(
            audio: [TrackOption(id: '1', language: 'zh')],
            video: [TrackOption(id: '2', width: 1920, height: 1080)],
            subtitle: [TrackOption(id: '3', language: 'zh')],
          ),
          lines: const ['唯一线路'],
          onLine: (_) {},
        ),
        isFalse,
      );
    });

    test('多条线路 / 多条画质 / 多条音轨，任意一条就摆', () {
      expect(
        TrackPanel.worthShowing(
          choices: const TrackChoices(),
          lines: const ['线路一', '线路二'],
          onLine: (_) {},
        ),
        isTrue,
      );
      expect(
        TrackPanel.worthShowing(
          choices: const TrackChoices(
            video: [
              TrackOption(id: '1', width: 3840, height: 2160),
              TrackOption(id: '2', width: 1280, height: 720),
            ],
          ),
        ),
        isTrue,
      );
      expect(
        TrackPanel.worthShowing(
          choices: const TrackChoices(
            audio: [
              TrackOption(id: '1', title: '国语'),
              TrackOption(id: '2', title: '粤语'),
            ],
          ),
        ),
        isTrue,
      );
    });

    test('有多条线路但没人接切换时也不摆（点了什么都不会发生）', () {
      expect(
        TrackPanel.worthShowing(
          choices: const TrackChoices(),
          lines: const ['线路一', '线路二'],
        ),
        isFalse,
      );
    });
  });
}
