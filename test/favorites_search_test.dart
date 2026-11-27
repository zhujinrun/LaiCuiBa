import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/ui/widgets/manage_folders_sheet.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('收藏搜索开关只在打开时保留查询词', () async {
    final store = await AppStore.load();
    expect(store.favoritesSearchOpen, isFalse);
    store.toggleFavoritesSearch();
    store.setFavoritesQuery('尚公主');
    expect(store.favoritesSearchOpen, isTrue);
    expect(store.favoritesQuery, '尚公主');
    store.toggleFavoritesSearch();
    expect(store.favoritesSearchOpen, isFalse);
    expect(store.favoritesQuery, '');
  });

  testWidgets('追剧空态的登录弹窗如实说明授权流程', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showTraktLoginDialog(tester.element(find.byType(Scaffold))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Trakt 追更'), findsOneWidget);
    expect(find.textContaining('已授权的应用可在 Trakt 网站设置'), findsOneWidget);
  });
}
