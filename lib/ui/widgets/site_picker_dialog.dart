import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/widgets/widget_center.dart';

/// Picks which site the home feed speaks for.
///
/// The original keeps this on the source (`homeSite`), and the chip in the home
/// header is how you change it. A source can declare dozens of sites -- the
/// seeded one declares 59 -- so the list gets a filter box rather than a wall of
/// names; every entry is an enabled site of the active source.
Future<void> showSitePicker(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierColor: const Color(0x33000000),
    builder: (_) => const _SitePickerDialog(),
  );
}

class _SitePickerDialog extends StatefulWidget {
  const _SitePickerDialog();

  @override
  State<_SitePickerDialog> createState() => _SitePickerDialogState();
}

class _SitePickerDialogState extends State<_SitePickerDialog> {
  final _filter = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final source = store.currentSource;
    final sites = source?.searchableSites ?? const <SiteInfo>[];
    final current = store.homeSite;
    final needle = _query.trim();
    final shown = needle.isEmpty
        ? sites
        : sites.where((site) => site.name.contains(needle)).toList();

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '选择站点',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: LcbColors.text,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      CupertinoIcons.xmark,
                      size: 15,
                      color: LcbColors.textTertiary,
                    ),
                    splashRadius: 16,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                source == null
                    ? '还没有可用的源'
                    : '首页与详情按这个站点取数 · ${sites.length} 个可选',
                style: const TextStyle(
                  fontSize: 12,
                  color: LcbColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: LcbColors.searchFill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.search,
                      size: 14,
                      color: LcbColors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _filter,
                        onChanged: (value) => setState(() => _query = value),
                        style: const TextStyle(fontSize: 13),
                        cursorHeight: 16,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: '搜索站点',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: LcbColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '自定义页面',
                style: TextStyle(
                  fontSize: 12,
                  color: LcbColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              _PageChoice(
                label: '使用资源自己的首页',
                selected: store.settings.homePageId.isEmpty,
                onTap: () async {
                  await WidgetCenter.setHomePage(store, null);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              for (final page in WidgetCenter.pages(store)) ...[
                _PageChoice(
                  label: page.displayName,
                  selected: store.settings.homePageId == page.id,
                  onTap: () async {
                    await WidgetCenter.setHomePage(store, page.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              SizedBox(
                height: 320,
                child: shown.isEmpty
                    ? const Center(
                        child: Text(
                          '没有匹配的站点',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: LcbColors.textTertiary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: shown.length,
                        itemBuilder: (_, index) {
                          final site = shown[index];
                          final selected = site.key == current?.key;
                          return InkWell(
                            onTap: () async {
                              await store.selectHomeSite(site.key);
                              if (context.mounted) Navigator.of(context).pop();
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              height: 42,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      site.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: selected
                                            ? LcbColors.primaryDim
                                            : LcbColors.text,
                                      ),
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(
                                      CupertinoIcons.checkmark_alt,
                                      size: 16,
                                      color: LcbColors.primaryDim,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageChoice extends StatelessWidget {
  const _PageChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? LcbColors.primaryDim : LcbColors.text,
                ),
              ),
            ),
            if (selected)
              const Icon(
                CupertinoIcons.checkmark_alt,
                size: 16,
                color: LcbColors.primaryDim,
              ),
          ],
        ),
      ),
    );
  }
}
