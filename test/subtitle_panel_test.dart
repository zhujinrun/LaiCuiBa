import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/track_choice.dart';
import 'package:lai_cui_ba/ui/widgets/subtitle_panel.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: child),
  ),
);

void main() {
  testWidgets('一条字幕轨都没有时也说清，并留着本地文件这条路', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SubtitlePanel(choices: const TrackChoices(), onPickSubtitleFile: () {}),
      ),
    );

    expect(find.text('这一集没有内嵌字幕'), findsOneWidget);
    expect(find.text('搜索字幕网站…'), findsOneWidget);
    expect(find.text('选择本地字幕文件…'), findsOneWidget);
    // 没挂字幕时不该有「取消外挂字幕」这一行。
    expect(find.text('不再使用外挂字幕'), findsNothing);
  });

  testWidgets('内嵌字幕带一个「关闭」，点关闭报的是 no', (tester) async {
    TrackOption? picked;
    await tester.pumpWidget(
      _wrap(
        SubtitlePanel(
          choices: const TrackChoices(
            subtitle: [
              TrackOption(id: '2', language: 'zh'),
              TrackOption(id: '3', language: 'en'),
            ],
            subtitleId: '2',
          ),
          onSubtitle: (t) => picked = t,
        ),
      ),
    );

    expect(find.text('字幕'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    expect(picked?.id, 'no');
  });

  testWidgets('挂上字幕后面板显示它是哪一份，并给一个取消入口', (tester) async {
    var cleared = 0;
    await tester.pumpWidget(
      _wrap(
        SubtitlePanel(
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

  testWidgets('字幕网站行点击后交给播放页去搜', (tester) async {
    var searched = 0;
    await tester.pumpWidget(
      _wrap(
        SubtitlePanel(
          choices: const TrackChoices(),
          onSearchSubtitles: () => searched++,
        ),
      ),
    );
    await tester.tap(find.text('搜索字幕网站…'));
    await tester.pump();
    expect(searched, 1);
  });
}
