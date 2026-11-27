import '../../models/models.dart';
import '../../services/store.dart';
import '../../services/widgets/widget_models.dart';

/// 一个组件区域真正取到的答案。失败和「今天没有内容」是两回事：前者说清
/// 原因并给重试，后者是源的真实回答，绝不拿假片单填空。
class SectionData {
  const SectionData({this.items = const [], this.error});

  final List<MediaItem> items;
  final String? error;

  bool get failed => error != null;
}

/// 组件区域的数据出口，对应原版 `ui/custom/section_data.dart`。
///
/// 目前只有「资源分类」有真数据源；组件仓库 / TMDB 会在界面上明说还没接，
/// 不会假装那里永远空着，也不会伪造内容。
class SectionDataLoader {
  SectionDataLoader._();

  static Future<SectionData> load(AppStore store, PageSection section) async {
    switch (section.source) {
      case SectionSource.category:
        if (section.categoryId.isEmpty) {
          return const SectionData(error: '这个区域还没有选分类');
        }
        try {
          final items = await store.categoryReal(section.categoryId);
          return SectionData(items: items);
        } on Object catch (error) {
          return SectionData(error: '$error');
        }
      case SectionSource.widget:
        return const SectionData(error: '还没有导入组件仓库');
      case SectionSource.tmdb:
        return const SectionData(error: 'TMDB 数据源还没接');
    }
  }
}
