import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../services/widgets/widget_center.dart';
import '../../services/widgets/widget_models.dart';
import 'section_data.dart';
import 'section_views.dart';

/// 把自定义页面画成首页，对应原版 `ui/custom/custom_home.dart`。
class CustomHomePage extends StatefulWidget {
  const CustomHomePage({super.key, required this.pageId});

  final String pageId;

  @override
  State<CustomHomePage> createState() => _CustomHomePageState();
}

class _CustomHomePageState extends State<CustomHomePage> {
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final page = WidgetCenter.page(store, widget.pageId);
    if (page == null) {
      return const Center(
        child: Text(
          '这个页面已经被删除，请在首页左上角换回资源自己的首页',
          style: TextStyle(fontSize: 14, color: LcbColors.textSecondary),
        ),
      );
    }
    return ColoredBox(
      color: page.translucent ? Colors.transparent : LcbColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 40),
        children: [
          if (page.sections.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Text(
                  '这个页面还没有组件',
                  style: TextStyle(fontSize: 14, color: LcbColors.textSecondary),
                ),
              ),
            ),
          for (final section in page.sections) ...[
            _CustomSection(
              key: ValueKey('${section.id}-$_reload'),
              section: section,
              onRetry: () => setState(() => _reload++),
            ),
            const SizedBox(height: 30),
          ],
        ],
      ),
    );
  }
}

class _CustomSection extends StatefulWidget {
  const _CustomSection({super.key, required this.section, required this.onRetry});

  final PageSection section;
  final VoidCallback onRetry;

  @override
  State<_CustomSection> createState() => _CustomSectionState();
}

class _CustomSectionState extends State<_CustomSection> {
  late Future<SectionData> _future = _load();

  Future<SectionData> _load() =>
      SectionDataLoader.load(StoreScope.of(context), widget.section);

  void _retry() {
    setState(() => _future = _load());
    widget.onRetry();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SectionData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: LcbMetrics.pagePadding,
              vertical: 24,
            ),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: LcbColors.primary,
                ),
              ),
            ),
          );
        }
        if (data.failed) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LcbMetrics.pagePadding,
              vertical: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data.error}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: LcbColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(CupertinoIcons.refresh, size: 14),
                  label: const Text('重试'),
                ),
              ],
            ),
          );
        }
        return SectionViewWidget(
          section: widget.section,
          items: data.items,
          onRetry: _retry,
        );
      },
    );
  }
}
