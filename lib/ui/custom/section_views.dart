import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/detail_nav.dart';
import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/widgets/widget_center.dart';
import '../../services/widgets/widget_models.dart';
import '../widgets/hero_banner.dart';
import '../widgets/media_card.dart';
import '../widgets/rail.dart';
import 'widget_search_dialog.dart';

/// 一个组件区域按选中的展示方式画出来，对应原版 `section_views.dart`。
class SectionViewWidget extends StatelessWidget {
  const SectionViewWidget({
    super.key,
    required this.section,
    required this.items,
    required this.onRetry,
  });

  final PageSection section;
  final List<MediaItem> items;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final title = section.title.trim().isEmpty
        ? section.categoryName
        : section.title.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: LcbMetrics.pagePadding),
          child: Row(
            children: [
              Expanded(
                child: SectionHeader(title: title.isEmpty ? '组件区域' : title),
              ),
              if (section.source == SectionSource.widget)
                IconButton(
                  onPressed: () => _search(context),
                  icon: const Icon(CupertinoIcons.search, size: 16),
                  color: LcbColors.textSecondary,
                  tooltip: '搜索组件内容',
                  splashRadius: 18,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: LcbMetrics.pagePadding,
              vertical: 18,
            ),
            child: Text(
              '这个区域还没有内容',
              style: TextStyle(
                fontSize: 13,
                color: LcbColors.textSecondary,
              ),
            ),
          )
        else
          switch (section.view) {
            SectionView.hero => HeroBanner(items: items.take(8).toList()),
            SectionView.grid => _grid(context, items),
            SectionView.list => _list(context, items),
            SectionView.rail => _rail(context, items),
          },
      ],
    );
  }

  Future<void> _search(BuildContext context) async {
    final store = StoreScope.of(context);
    final widget = WidgetCenter.widget(store, section.widgetId);
    if (widget == null) return;
    WidgetModule? module;
    for (final candidate in widget.modules) {
      if (candidate.id == section.moduleId) module = candidate;
    }
    module ??= widget.modules.firstOrNull;
    if (module == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => WidgetSearchDialog(
        section: section,
        widget: widget,
        module: module!,
      ),
    );
  }

  Widget _rail(BuildContext context, List<MediaItem> items) {
    final width = HomePosterWidth.of(context);
    return LcbRail(
      height: width * 1.5 + 30,
      artHeight: width * 1.5,
      cardWidth: width,
      itemCount: items.length,
      itemBuilder: (_, i) => PosterCard(
        item: items[i],
        width: width,
        onTap: () => LcbDetailScope.openOf(context, items[i]),
      ),
    );
  }

  Widget _grid(BuildContext context, List<MediaItem> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LcbMetrics.pagePadding),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 18,
          crossAxisSpacing: LcbMetrics.posterGap,
          childAspectRatio: 2 / 3,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => PosterCard(
          item: items[i],
          width: 180,
          onTap: () => LcbDetailScope.openOf(context, items[i]),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<MediaItem> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LcbMetrics.pagePadding),
      child: Column(
        children: [
          for (final item in items)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => LcbDetailScope.openOf(context, item),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 56,
                        height: 78,
                        child: item.image == null || item.image!.isEmpty
                            ? const Icon(
                                CupertinoIcons.photo,
                                color: LcbColors.textTertiary,
                              )
                            : Image.network(
                                item.image!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                  CupertinoIcons.photo,
                                  color: LcbColors.textTertiary,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: LcbColors.text,
                            ),
                          ),
                          if (item.subtitle != null && item.subtitle!.isNotEmpty)
                            Text(
                              item.subtitle!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: LcbColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 和首页同一条收缩规则：卡片随内容宽度变化，不把海报放大到失真。
class HomePosterWidth {
  static double of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final content = width - LcbMetrics.pagePadding * 2 - 220;
    return HomePagePosterWidth.value(content);
  }
}

/// 单独抽出来，避免 section_views 反向 import home_page。
class HomePagePosterWidth {
  static double value(double contentWidth) =>
      contentWidth < 480 ? 130 : (contentWidth / 7.25).clamp(130.0, 196.0);
}
