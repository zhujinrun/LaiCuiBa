import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/core/store_scope.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/ui/pages/detail_page.dart';
import 'package:lai_cui_ba/ui/widgets/poster_art.dart';

/// 真实猫源给的是 `vod_pic` 网络地址。详情页以前用 Image.asset 画它，
/// 于是首页「继续观看」卡片有封面、点进详情却是一块灰底。
/// 海报位和模糊背景都必须走 PosterArt（内部按 http(s) 选 Image.network）。
void main() {
  testWidgets('详情页把网络 vod_pic 当网络图渲染', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();

    const item = MediaItem(
      id: '575857',
      title: '尚公主',
      image: 'https://img.example.com/poster.webp',
      posterSeed: 42,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StoreScope(
          store: store,
          child: const DetailPage(item: item),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PosterArt), findsNWidgets(2));
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(
      images.where((i) => i.image is NetworkImage).length,
      greaterThanOrEqualTo(1),
      reason: '详情页必须让 Image.network 拿到真实 vod_pic',
    );
    expect(
      images.where((i) => i.image is AssetImage),
      isEmpty,
      reason: '网络 URL 不能再被当作本地资源',
    );
  });
}
