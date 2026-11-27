import '../../models/models.dart';
import '../../services/store.dart';
import '../../services/tmdb.dart';
import '../../services/widgets/widget_center.dart';
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
        return _widget(store, section);
      case SectionSource.tmdb:
        return _tmdb(store, section);
    }
  }
}

/// 组件仓库数据源。原版的说法是组件运行在沙箱里但仍能访问网络；这里的宿主
/// 是有超时的独立 Node 进程，组件报错按原版文案原样摆出来。
Future<SectionData> _widget(AppStore store, PageSection section) async {
  if (section.widgetId.isEmpty || section.moduleId.isEmpty) {
    return const SectionData(error: '这个区域还没有选组件');
  }
  final widget = WidgetCenter.widget(store, section.widgetId);
  if (widget == null) {
    return const SectionData(error: '组件仓库或数据源已被删除');
  }
  final runtime = store.widgets;
  if (runtime == null) {
    return const SectionData(error: '当前设备不支持运行组件');
  }
  final module = widget.modules.firstWhere(
    (candidate) => candidate.id == section.moduleId,
    orElse: () => widget.modules.first,
  );
  try {
    final answer = await runtime.load(
      widget.scriptPath,
      module.functionName,
      section.params.isEmpty ? const {'page': 1} : section.params,
    );
    return SectionData(
      items: [
        for (final item in answer.items)
          WidgetMediaMapper.map(item, module.title, widget.id),
      ],
    );
  } on Object catch (error) {
    return SectionData(error: '$error');
  }
}

class WidgetMediaMapper {
  static MediaItem map(
    Map<String, dynamic> item,
    String lineName,
    String widgetId,
  ) {
    final video = '${item['videoUrl'] ?? ''}';
    final link = '${item['link'] ?? ''}';
    final description = '${item['description'] ?? ''}';
    final rawId = '${item['id'] ?? ''}';
    return MediaItem(
      // 有详情链接的条目把 link 放在 id 上，detailReal 会交给 loadDetail 解析。
      id: video.isEmpty && link.isNotEmpty ? link : rawId,
      title: '${item['title'] ?? ''}',
      subtitle: description.isEmpty ? null : description,
      overview: link.isEmpty ? null : '详情链接：$link',
      image: '${item['image'] ?? ''}',
      tag: '${item['mediaType'] ?? ''}'.isEmpty ? null : '${item['mediaType']}',
      playLines: video.isEmpty
          ? const []
          : [
              PlayLine(
                name: lineName,
                episodes: [PlayEpisode(label: '正片', url: video)],
              ),
            ],
      siteKey: 'widget:$widgetId',
    );
  }
}

Future<SectionData> _tmdb(AppStore store, PageSection section) async {
  final key = store.settings.tmdbApiKey.trim();
  if (key.isEmpty) {
    return const SectionData(error: '请先到设置配置 TMDB API Key');
  }
  final kind = section.categoryId == 'tv' ? 'tv' : 'movie';
  try {
    return SectionData(items: await TmdbService.trending(key, kind: kind));
  } on Object catch (error) {
    return SectionData(error: '$error');
  }
}
