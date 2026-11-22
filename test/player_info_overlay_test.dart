import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lai_cui_ba/services/player_info.dart';
import 'package:lai_cui_ba/ui/widgets/player_info_overlay.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('PlayerInfoOverlay', () {
    testWidgets('renders each fact as 标签 值, joined', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlayerInfoOverlay(
            facts: [
              PlayerInfoFact('分辨率', '1920×1080'),
              PlayerInfoFact('帧率', '23.976 fps'),
              PlayerInfoFact('码率', '2543 kbps'),
            ],
          ),
        ),
      );
      expect(find.text('分辨率 1920×1080  ·  帧率 23.976 fps  ·  码率 2543 kbps'), findsOneWidget);
    });

    testWidgets('null value shows --', (tester) async {
      await tester.pumpWidget(
        _wrap(const PlayerInfoOverlay(facts: [PlayerInfoFact('帧率', null)])),
      );
      expect(find.text('帧率 --'), findsOneWidget);
    });
  });

  group('MiniProgressBar', () {
    testWidgets('played segment is the primary color', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MiniProgressBar(
            position: Duration(seconds: 30),
            buffer: Duration(seconds: 60),
            duration: Duration(seconds: 120),
          ),
        ),
      );
      final boxes = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(MiniProgressBar),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();
      // 底层缓冲(浅蓝) + 上层已播(主题紫)
      expect(boxes, hasLength(2));
      expect(boxes.last.color, const Color(0xFF7B68EE));
    });

    testWidgets('unknown duration draws nothing (zero width)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MiniProgressBar(
            position: Duration.zero,
            buffer: Duration.zero,
            duration: Duration.zero,
          ),
        ),
      );
      final bars = tester
          .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .toList();
      expect(bars, hasLength(2));
      expect(bars[0].widthFactor, 0.0);
      expect(bars[1].widthFactor, 0.0);
    });
  });
}
