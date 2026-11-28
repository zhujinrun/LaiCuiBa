import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/core/store_scope.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/ui/widgets/media_card.dart';
import 'package:lai_cui_ba/ui/widgets/rail.dart';

/// 海报卡标题行高 14 * 1.43 = 20.02，rail 只给 20px。小数宽度下（用户实测
/// 154.3）这个差值加舍入会溢出 0.2px 触发黄黑条纹。标题必须钉死在 20px 内。
void main() {
  for (final width in [154.3, 154.7, 196.0, 150.6]) {
    testWidgets('PosterCard 标题在 ${width}px 宽下不溢出 rail', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (details) {
        final message = details.exception.toString();
        if (message.contains('overflowed')) {
          overflows.add(message);
        } else {
          prev?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = prev);

      await tester.pumpWidget(
        MaterialApp(
          home: StoreScope(
            store: store,
            child: Scaffold(
              body: SizedBox(
                width: 800,
                child: LcbRail(
                  height: width * 1.5 + 10 + 20,
                  artHeight: width * 1.5,
                  cardWidth: width,
                  itemCount: 8,
                  itemBuilder: (_, i) => PosterCard(
                    item: MediaItem(
                      id: 'p$i',
                      title: '很长很长的片名测试${i + 1}',
                      posterSeed: i,
                    ),
                    width: width,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(overflows, isEmpty,
          reason: '宽度 $width 下标题不应溢出，实际: $overflows');
    });
  }

  testWidgets('拖动窗口缩小时海报高度立即跟随，动画中间帧不溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    final overflows = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (details) {
      final m = details.exception.toString();
      if (m.contains('overflowed')) overflows.add(m);
    };
    addTearDown(() => FlutterError.onError = prev);

    Widget build(double w) => MaterialApp(
          home: StoreScope(
            store: store,
            child: Scaffold(
              body: SizedBox(
                width: 800,
                child: LcbRail(
                  height: w * 1.5 + 10 + 20,
                  artHeight: w * 1.5,
                  cardWidth: w,
                  itemCount: 8,
                  itemBuilder: (_, i) => PosterCard(
                    item: MediaItem(id: 'p$i', title: '片名$i', posterSeed: i),
                    width: w,
                  ),
                ),
              ),
            ),
          ),
        );

    // Start wide, then shrink like a window drag. The art's height must not
    // animate behind the rail's tight height, or the mid-flight frame
    // overflows by ~24px (the stripes the user saw while dragging).
    await tester.pumpWidget(build(196));
    await tester.pumpAndSettle();
    for (final target in [180.0, 165.0, 150.0]) {
      await tester.pumpWidget(build(target));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80)); // mid-animation
      expect(overflows, isEmpty,
          reason: '缩到 $target 的动画中间帧不应溢出，实际: $overflows');
      await tester.pumpAndSettle();
    }
  });
}
