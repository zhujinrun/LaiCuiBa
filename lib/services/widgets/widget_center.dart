import '../../services/store.dart';
import 'widget_models.dart';

/// 自定义页面的增删与「首页显示哪个页面」，对应原版 `widget_center.dart`。
///
/// 页面表挂在 [AppSettings.customPages] 上（原始 JSON），这里负责解释成模型，
/// 所以设置备份会把页面一起带走，而模型层不需要 import services。
class WidgetCenter {
  WidgetCenter._();

  static List<CustomPage> pages(AppStore store) => [
    for (final raw in store.settings.customPages)
      if ((raw['id'] as String?)?.isNotEmpty ?? false)
        CustomPage.fromJson(raw),
  ];

  static CustomPage? page(AppStore store, String id) {
    for (final page in pages(store)) {
      if (page.id == id) return page;
    }
    return null;
  }

  static CustomPage? homePage(AppStore store) {
    final id = store.settings.homePageId;
    return id.isEmpty ? null : page(store, id);
  }

  static Future<void> savePage(AppStore store, CustomPage page) async {
    final updated = pages(store);
    final index = updated.indexWhere((candidate) => candidate.id == page.id);
    if (index >= 0) {
      updated[index] = page;
    } else {
      updated.add(page);
    }
    await _write(store, updated, store.settings.homePageId);
  }

  static Future<void> deletePage(AppStore store, String id) async {
    final updated = pages(store)..removeWhere((page) => page.id == id);
    final home = store.settings.homePageId == id ? '' : store.settings.homePageId;
    await _write(store, updated, home);
  }

  /// 空 id 表示回到资源自己的首页。
  static Future<void> setHomePage(AppStore store, String? id) async {
    final pageId = id == null || id.isEmpty ? '' : id;
    if (pageId.isNotEmpty && page(store, pageId) == null) return;
    await _write(store, pages(store), pageId);
  }

  static Future<void> _write(
    AppStore store,
    List<CustomPage> pages,
    String homePageId,
  ) async {
    await store.updateSettings(
      store.settings.copyWith(
        customPages: [for (final page in pages) page.toJson()],
        homePageId: homePageId,
      ),
    );
  }
}
