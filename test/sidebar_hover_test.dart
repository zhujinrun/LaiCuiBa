import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/core/store_scope.dart';
import 'package:lai_cui_ba/core/theme.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/ui/shell.dart';

/// 侧栏导航的悬浮背景必须是瞬时高亮（和原版一致）。曾经这里用了一个
/// 140ms 的 AnimatedContainer，鼠标划过时每个 item 只来得及显示半透明的
/// 渐变中间帧就淡出，读起来像「背景闪烁」。
void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    await tester.pumpWidget(
      MaterialApp(
        home: StoreScope(store: store, child: const Shell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 侧栏在最左，取 x 最小的那个文本元素，避开页面内容里的同名文字。
  Element leftmost(WidgetTester tester, String text) {
    final els = find.text(text).evaluate().toList()
      ..sort((a, b) => tester
          .getRect(find.byWidget(a.widget))
          .left
          .compareTo(tester.getRect(find.byWidget(b.widget)).left));
    return els.first;
  }

  Rect elementRect(WidgetTester tester, Element el) {
    final ro = el.renderObject! as RenderBox;
    return ro.localToGlobal(Offset.zero) & ro.size;
  }

  Color navBackground(Element textEl) {
    final box = textEl.findAncestorRenderObjectOfType<RenderDecoratedBox>();
    return (box?.decoration as BoxDecoration?)?.color ?? const Color(0x00000000);
  }

  testWidgets('侧栏悬浮背景瞬时高亮，无 140ms 渐变', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpShell(tester);

    // 默认在首页，「设置」是非选中项，hover 时背景应从透明变灰。
    final el = leftmost(tester, '设置');
    final center = elementRect(tester, el).center;
    final untouched = navBackground(el);
    expect(untouched, isNot(LcbColors.hover), reason: '未悬浮时不应是 hover 色');

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    await tester.pump();
    await gesture.moveTo(center);
    // 只推进一帧，不推进虚拟时间：普通 Container 应立即到 hover 色；
    // 若是 AnimatedContainer，此刻仍接近透明（140ms 动画才刚开始）。
    await tester.pump();

    expect(navBackground(el), LcbColors.hover,
        reason: '进入一帧后就应是完整 hover 色，不能是渐变中间态');

    // 侧栏 item 里不应再出现做背景动画的 AnimatedContainer。
    expect(
      el.findAncestorWidgetOfExactType<AnimatedContainer>(),
      isNull,
      reason: '侧栏导航不再用 AnimatedContainer 做悬浮背景',
    );

    await gesture.moveTo(const Offset(400, 500));
    await tester.pump();
    expect(navBackground(el), isNot(LcbColors.hover), reason: '移出后立即恢复');
  });
}
