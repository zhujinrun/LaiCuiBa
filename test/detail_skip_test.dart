import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/core/store_scope.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/skip_rule.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/ui/pages/detail_page.dart';

const _item = MediaItem(
  id: 'm',
  title: '一部剧',
  episodes: ['第1集', '第2集'],
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('详情页能看和清本剧片头片尾', (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await AppStore.load();
    await store.setSkipOverride(
      _item.title,
      const SkipOverride(introMs: 30000),
    );

    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: const MaterialApp(
          home: Scaffold(body: DetailPage(item: _item)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('片头片尾'), findsOneWidget);
    expect(find.text('片头 30 秒 · 片尾 不跳过'), findsOneWidget);
    expect(find.text('本剧单独设置过'), findsOneWidget);

    await tester.tap(find.text('片头 30 秒 · 片尾 不跳过'));
    await tester.pumpAndSettle();
    expect(find.text('本剧片头片尾'), findsNWidgets(2));
    expect(find.text('清除本剧设置'), findsNWidgets(2));

    await tester.tap(find.text('清除本剧设置').last);
    await tester.pumpAndSettle();
    expect(store.skipOverrideFor(_item.title).isEmpty, isTrue);
  });
}
