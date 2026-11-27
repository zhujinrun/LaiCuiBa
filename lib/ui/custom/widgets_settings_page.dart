import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../services/widgets/widget_center.dart';
import '../../services/widgets/widget_models.dart';
import 'page_editor.dart';
import 'widget_repo_settings.dart';

/// 设置里的「自定义页面」子页，对应原版 `widgets_settings_page.dart`。
class CustomPagesSettings extends StatefulWidget {
  const CustomPagesSettings({super.key});

  @override
  State<CustomPagesSettings> createState() => _CustomPagesSettingsState();
}

class _CustomPagesSettingsState extends State<CustomPagesSettings> {
  late List<CustomPage> _pages = WidgetCenter.pages(StoreScope.of(context));
  late String _homeId = StoreScope.of(context).settings.homePageId;

  void _reload() {
    final store = StoreScope.of(context);
    setState(() {
      _pages = WidgetCenter.pages(store);
      _homeId = store.settings.homePageId;
    });
  }

  Future<void> _create() async {
    final saved = await showPageEditor(context);
    if (saved) _reload();
  }

  Future<void> _edit(CustomPage page) async {
    final saved = await showPageEditor(context, page: page);
    if (saved) _reload();
  }

  Future<void> _delete(CustomPage page) async {
    final store = StoreScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除页面'),
        content: const Text(
          '页面和其中的组件区域都会删除，已导入的组件仓库不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await WidgetCenter.deletePage(store, page.id);
    _reload();
  }

  Future<void> _setHome(CustomPage page) async {
    final store = StoreScope.of(context);
    await WidgetCenter.setHomePage(
      store,
      _homeId == page.id ? null : page.id,
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card([
          _row(
            icon: CupertinoIcons.add,
            title: '新建页面',
            subtitle: '导入组件仓库，搭建自定义首页页面',
            onTap: _create,
          ),
        ]),
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 12, 10, 6),
          child: Text(
            '点下方 + 新增组件区域：先选展示方式，再选数据来自哪个组件仓库、TMDB 或资源的分类。',
            style: TextStyle(fontSize: 12.5, color: LcbColors.textSecondary),
          ),
        ),
        const SizedBox(height: 10),
        if (_pages.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 24),
            child: Text(
              '还没有页面',
              style: TextStyle(fontSize: 14, color: LcbColors.textSecondary),
            ),
          ),
        for (final page in _pages) ...[
          _card([
            _row(
              icon: CupertinoIcons.rectangle_grid_2x2,
              title: page.displayName,
              subtitle: '${page.sections.length} 个组件区域',
              value: _homeId == page.id ? '当前首页' : null,
              onTap: () => _setHome(page),
            ),
            _row(
              icon: CupertinoIcons.pencil,
              title: '编辑',
              subtitle: '改名、改外观、增删组件区域',
              onTap: () => _edit(page),
            ),
            _row(
              icon: CupertinoIcons.trash,
              title: '删除',
              subtitle: '页面和其中的组件区域都会删除',
              onTap: () => _delete(page),
            ),
          ]),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 22),
        const WidgetRepoSettings(),
      ],
    );
  }

  Widget _card(List<Widget> rows) => DecoratedBox(
    decoration: BoxDecoration(
      color: LcbColors.card,
      borderRadius: BorderRadius.circular(LcbMetrics.settingsCardRadius),
    ),
    child: Column(children: rows),
  );

  Widget _row({
    required IconData icon,
    required String title,
    String? subtitle,
    String? value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: LcbMetrics.settingsRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 18, color: LcbColors.sysBlue),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: LcbColors.text,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: LcbColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (value != null)
                Text(
                  value,
                  style: const TextStyle(fontSize: 12, color: LcbColors.sysBlue),
                ),
              const Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: LcbColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
