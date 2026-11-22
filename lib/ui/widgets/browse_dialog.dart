import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../services/spider_client.dart';

/// What the browse panel was asked to show: one category plus any narrowing
/// conditions, ready for `GridPage`.
class BrowseChoice {
  const BrowseChoice({
    required this.title,
    required this.typeId,
    this.filters = const {},
  });

  /// The category's display name, e.g. 电影.
  final String title;

  final String typeId;

  /// Only the picks that narrow the list (`class` / `area` / `year` / `by`),
  /// with empty values dropped.
  final Map<String, String> filters;
}

/// The original's 「浏览内容」 panel: every category the site declares, the
/// filters that category offers, and one button to open the grid.
///
/// Opened from the ⊞ button in the home header. The data is the site's own
/// `home` answer -- a category with no filters shows just the category row,
/// and a source that does not answer shows the failure instead of an empty
/// picker that reads like the site has nothing.
Future<BrowseChoice?> showBrowseDialog(
  BuildContext context, {
  Future<SpiderHome?> Function()? load,
}) {
  // `??` is lazy, so a test that injects the data never touches the store.
  final loader = load ?? StoreScope.of(context).browseHome;
  return showDialog<BrowseChoice>(
    context: context,
    barrierColor: const Color(0x33000000),
    builder: (_) => _BrowseSheet(load: loader),
  );
}

class _BrowseSheet extends StatefulWidget {
  const _BrowseSheet({required this.load});

  final Future<SpiderHome?> Function() load;

  @override
  State<_BrowseSheet> createState() => _BrowseSheetState();
}

class _BrowseSheetState extends State<_BrowseSheet> {
  SpiderHome? _home;
  String? _error;
  bool _loading = true;

  /// The chosen category, and the picks per filter group key.
  String _tid = '';
  final Map<String, String> _picked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final home = await widget.load();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _home = home;
      if (home == null) {
        _error = '这个站点没有答上来';
        return;
      }
      if (home.classes.isEmpty) {
        _error = '这个站点没有分类';
        return;
      }
      _tid = home.classes.first.typeId;
    });
  }

  /// The groups for the chosen category. Switching category drops the old
  /// picks: the ids behind `class 喜剧` on 电影 mean nothing under 剧集.
  List<SpiderFilterGroup> get _groups =>
      _home?.groupsFor(_tid) ?? const <SpiderFilterGroup>[];

  void _pickCategory(String tid) {
    if (tid == _tid) return;
    setState(() {
      _tid = tid;
      _picked.clear();
    });
  }

  void _pickFilter(SpiderFilterGroup group, String value) {
    setState(() {
      if (value.isEmpty) {
        _picked.remove(group.key);
      } else {
        _picked[group.key] = value;
      }
    });
  }

  String get _title {
    for (final c in _home?.classes ?? const <SpiderClass>[]) {
      if (c.typeId == _tid) return c.name;
    }
    return '';
  }

  void _submit() {
    Navigator.of(context).pop(
      BrowseChoice(
        title: _title,
        typeId: _tid,
        filters: Map<String, String>.unmodifiable(_picked),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: LcbColors.card,
      // The original anchors the panel to the top-left of the content column,
      // 15px in from the sidebar and 6px under the header -- not centred.
      alignment: Alignment.topLeft,
      insetPadding: const EdgeInsets.only(
        left: LcbMetrics.sidebarWidth + 8,
        top: 66,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 591,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Heading(),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 90),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: LcbColors.primaryDim,
                      ),
                    ),
                  ),
                )
              else if (_error != null)
                _Failure(message: _error!, onRetry: _load)
              else
                ..._buildPicker(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPicker() {
    final classes = _home?.classes ?? const <SpiderClass>[];
    return [
      const SizedBox(height: 22),
      const Text(
        '分类',
        style: TextStyle(fontSize: 12.5, color: LcbColors.textSecondary),
      ),
      const SizedBox(height: 10),
      _ChipRow(
        children: [
          for (final c in classes)
            _Chip(
              label: c.name,
              selected: c.typeId == _tid,
              onTap: () => _pickCategory(c.typeId),
            ),
        ],
      ),
      for (final group in _groups) ...[
        const SizedBox(height: 54),
        _ChipRow(
          children: [
            for (final option in _optionsOf(group))
              _Chip(
                label: option.label,
                selected: (_picked[group.key] ?? '') == option.value,
                onTap: () => _pickFilter(group, option.value),
              ),
          ],
        ),
      ],
      const SizedBox(height: 55),
      SizedBox(
        width: double.infinity,
        height: 40,
        child: TextButton(
          onPressed: _submit,
          style: TextButton.styleFrom(
            backgroundColor: LcbColors.primaryDim,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            _picked.isEmpty ? '查看$_title' : '查看筛选项结果',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    ];
  }

  /// The source's own options, with a 全部 in front when it did not ship one
  /// (the `by` group lists only 时间/人气/评分).
  static List<SpiderFilterOption> _optionsOf(SpiderFilterGroup group) {
    if (group.options.any((o) => o.value.isEmpty)) return group.options;
    return [
      const SpiderFilterOption(label: '全部', value: ''),
      ...group.options,
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              CupertinoIcons.square_grid_2x2,
              size: 16,
              color: LcbColors.primaryDim,
            ),
            const SizedBox(width: 8),
            const Text(
              '浏览内容',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: LcbColors.text,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  CupertinoIcons.xmark,
                  size: 15,
                  color: LcbColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '选好分类与筛选条件后查看',
          style: TextStyle(fontSize: 12.5, color: LcbColors.textSecondary),
        ),
      ],
    );
  }
}

/// One horizontally scrollable row of chips. The source can declare more
/// options than fit (17 years), and the original keeps them on one line.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? LcbColors.primaryDim : LcbColors.searchFill,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: selected ? Colors.white : LcbColors.text,
          ),
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Text(
            message,
            style: const TextStyle(fontSize: 13, color: LcbColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
