import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/widgets/widget_models.dart';

void main() {
  test('页面与组件区域能原样往返 JSON', () {
    const page = CustomPage(
      id: 'page-1',
      name: '我的首页',
      iconId: 'cat',
      translucent: true,
      sections: [
        PageSection(
          id: 's1',
          title: '热门',
          view: SectionView.grid,
          source: SectionSource.category,
          categoryId: '1',
          categoryName: '电影',
          widgetId: 'w1',
          moduleId: 'popular',
        ),
        PageSection(
          id: 's2',
          title: '轮播',
          view: SectionView.hero,
          source: SectionSource.tmdb,
        ),
      ],
    );

    final restored = CustomPage.fromJson(page.toJson());
    expect(restored.id, 'page-1');
    expect(restored.name, '我的首页');
    expect(restored.translucent, isTrue);
    expect(restored.sections.length, 2);
    expect(restored.sections.first.view, SectionView.grid);
    expect(restored.sections.first.categoryId, '1');
    expect(restored.sections.first.widgetId, 'w1');
    expect(restored.sections.first.moduleId, 'popular');
    expect(restored.sections.last.source, SectionSource.tmdb);
  });

  test('空名字给未命名页面，坏 slug 退回可绘制的默认值', () {
    expect(const CustomPage(id: 'p').displayName, '未命名页面');
    final section = PageSection.fromJson({
      'id': 's',
      'view': 'nonsense',
      'source': 'nonsense',
    });
    expect(section.view, SectionView.rail);
    expect(section.source, SectionSource.category);
  });

  test('设置里的页面表也跟着 AppSettings 往返', () {
    const settings = AppSettings(
      customPages: [
        {'id': 'p', 'name': '第一页'},
      ],
      homePageId: 'p',
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.homePageId, 'p');
    expect(restored.customPages.single['name'], '第一页');
  });
}
