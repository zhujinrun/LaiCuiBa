import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/ui/widgets/detail_action_dialogs.dart';

Widget _host(VoidCallback onTap) => MaterialApp(
  home: Scaffold(
    body: Center(child: ElevatedButton(onPressed: onTap, child: const Text('open'))),
  ),
);

Future<void> _open(WidgetTester tester, VoidCallback onTap) async {
  await tester.pumpWidget(_host(onTap));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('换平台如实说没有跨源结果', (tester) async {
    await _open(tester, () => showPlatformDialog(tester.element(find.byType(Scaffold)), '尚公主'));
    expect(find.textContaining('换平台'), findsOneWidget);
    expect(find.textContaining('没有可用的跨源搜索结果'), findsOneWidget);
  });

  testWidgets('下载列出真实集数并说明引擎未接入', (tester) async {
    await _open(
      tester,
      () => showDownloadDialog(
        tester.element(find.byType(Scaffold)),
        ['第1集', '第2集'],
      ),
    );
    expect(find.text('下载'), findsOneWidget);
    expect(find.textContaining('下载引擎尚未接入'), findsOneWidget);
    expect(find.text('1. 第1集'), findsOneWidget);
  });

  testWidgets('追更没有账号时如实说明', (tester) async {
    await _open(tester, () => showFollowDialog(tester.element(find.byType(Scaffold)), '尚公主'));
    expect(find.textContaining('没有配置 Trakt / Bangumi'), findsOneWidget);
  });

  testWidgets('收藏到可以选择已有收藏夹', (tester) async {
    FavoritePick? picked;
    await _open(
      tester,
      () async => picked = await showFavoriteFolderDialog(
        tester.element(find.byType(Scaffold)),
        const [FavoriteFolder(id: 'f1', name: '好看的电影')],
      ),
    );
    expect(find.text('收藏到'), findsOneWidget);
    await tester.tap(find.text('好看的电影'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(picked?.folderId, 'f1');
  });
}
