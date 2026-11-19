import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/main.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/ui/shell.dart';

void main() {
  testWidgets('shell renders sidebar groups and hero headline', (tester) async {
    tester.view.physicalSize = const Size(1360, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();

    await tester.pumpWidget(LcbApp(store: store));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.byType(Shell), findsOneWidget);
    expect(find.text('LaiCuiBa'), findsOneWidget);
    for (final label in ['媒体库', '来源', '列表', '其他', '首页', '资源', '收藏', '历史', '设置']) {
      expect(find.text(label), findsWidgets, reason: 'sidebar label "$label" missing');
    }
    expect(find.text('继续观看'), findsOneWidget);
  });
}
