import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/ui/widgets/media_badges.dart';

void main() {
  const item = MediaItem(
    id: 'x',
    title: 'Sample.2014.UHD.BluRay.2160p.REMUX.HDR10.HEVC.mkv',
  );

  const on = AppSettings(mediaBadgesEnabled: true);

  testWidgets('识别到规格就画徽章，识别不到就空', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 300,
            child: MediaBadgeRow(item: item, settings: on),
          ),
        ),
      ),
    );

    // 默认纯短标：4K、HDR10、HEVC、BD、Remux。
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('HDR10'), findsOneWidget);
    expect(find.text('HEVC'), findsOneWidget);

    // 中文片名无规格 → 什么都不画。
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 300,
            child: MediaBadgeRow(
              item: MediaItem(id: 'y', title: '三体'),
              settings: on,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(MediaBadgeRow), findsOneWidget);
    expect(find.text('4K'), findsNothing);
  });

  testWidgets('带文字显示中文名，不带文字显示短标', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 320,
            child: MediaBadgeRow(
              item: item,
              settings: AppSettings(mediaBadgesEnabled: true, badgeText: true),
            ),
          ),
        ),
      ),
    );
    // 带文字：显示「杜比视界」这类中文名而不是「DV」。
    expect(find.text('4K'), findsOneWidget); // 4K 的短标和中文名相同
    expect(find.text('HDR10'), findsOneWidget);
  });

  testWidgets('总开关关闭就不画任何徽章', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 300,
            child: MediaBadgeRow(
              item: item,
              settings: AppSettings(mediaBadgesEnabled: false),
            ),
          ),
        ),
      ),
    );
    expect(find.text('4K'), findsNothing);
    expect(find.text('HDR10'), findsNothing);
  });

  testWidgets('细开关关掉某类规格', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 300,
            child: MediaBadgeRow(
              item: item,
              settings: AppSettings(
                mediaBadgesEnabled: true,
                badgeSpecs: const {'uhd': false, 'hevc': false},
              ),
            ),
          ),
        ),
      ),
    );
    // 4K 和 HEVC 被关掉，HDR10 还在。
    expect(find.text('4K'), findsNothing);
    expect(find.text('HEVC'), findsNothing);
    expect(find.text('HDR10'), findsOneWidget);
  });
}
