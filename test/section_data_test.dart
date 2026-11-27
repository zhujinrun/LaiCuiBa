import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/core/store_scope.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/services/widgets/widget_models.dart';
import 'package:lai_cui_ba/ui/custom/section_data.dart';
import 'package:lai_cui_ba/ui/custom/section_views.dart';

void main() {
  testWidgets('没接的数据源和没选的分类都如实说明，不摆假片单', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();

    final widget = await SectionDataLoader.load(
      store,
      const PageSection(id: 's', source: SectionSource.widget),
    );
    expect(widget.failed, isTrue);
    expect(widget.error, '这个区域还没有选组件');

    final missing = await SectionDataLoader.load(
      store,
      const PageSection(
        id: 's',
        source: SectionSource.widget,
        widgetId: 'not-imported',
        moduleId: 'popular',
      ),
    );
    expect(missing.error, '组件仓库或数据源已被删除');

    final tmdb = await SectionDataLoader.load(
      store,
      const PageSection(id: 's', source: SectionSource.tmdb),
    );
    expect(tmdb.error, '请先到设置配置 TMDB API Key');

    final empty = await SectionDataLoader.load(
      store,
      const PageSection(id: 's', source: SectionSource.category),
    );
    expect(empty.error, '这个区域还没有选分类');
  });

  testWidgets('区域按展示方式画出来，空区域不伪造内容', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const section = PageSection(
      id: 's',
      title: '电影',
      view: SectionView.grid,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SectionViewWidget(
              section: section,
              items: const [],
              onRetry: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('这个区域还没有内容'), findsOneWidget);

    const item = MediaItem(id: 'm', title: '一部真电影');
    final store = await AppStore.load();
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SectionViewWidget(
                section: section,
                items: const [item],
                onRetry: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('一部真电影'), findsOneWidget);
  });
}
