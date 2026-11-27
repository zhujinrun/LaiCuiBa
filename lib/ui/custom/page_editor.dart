import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../services/app_icons.dart';
import '../../services/spider_client.dart';
import '../../services/widgets/widget_center.dart';
import '../../services/widgets/widget_models.dart';

Future<bool> showPageEditor(
  BuildContext context, {
  CustomPage? page,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x60000000),
    builder: (_) => _PageEditor(page: page),
  );
  return saved ?? false;
}

class _PageEditor extends StatefulWidget {
  const _PageEditor({this.page});

  final CustomPage? page;

  @override
  State<_PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<_PageEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.page?.name ?? '',
  );
  late String _iconId = widget.page?.iconId ?? '';
  late bool _translucent = widget.page?.translucent ?? false;
  late List<PageSection> _sections = [
    ...widget.page?.sections ?? const <PageSection>[],
  ];
  late final Future<List<SpiderClass>> _categories = StoreScope.of(
    context,
  ).homeCategoriesReal();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final page = CustomPage(
      id: widget.page?.id ?? newPageId(),
      name: _name.text.trim(),
      iconId: _iconId,
      translucent: _translucent,
      sections: _sections,
    );
    await WidgetCenter.savePage(StoreScope.of(context), page);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _addSection() async {
    final categories = await _categories;
    if (!mounted) return;
    if (categories.isEmpty) {
      setState(() => _error = '这个资源没有分类，先给资源加一个可用的站点');
      return;
    }
    final edited = await showDialog<PageSection>(
      context: context,
      builder: (_) => _SectionEditor(
        categories: categories,
        section: PageSection(
          id: newSectionId(),
          categoryId: categories.first.typeId,
          categoryName: categories.first.name,
        ),
      ),
    );
    if (edited == null) return;
    setState(() {
      _sections = [..._sections, edited];
      _error = null;
    });
  }

  Future<void> _editSection(int index) async {
    final original = _sections[index];
    final categories = await _categories;
    if (!mounted) return;
    final edited = await showDialog<PageSection>(
      context: context,
      builder: (_) => _SectionEditor(
        categories: categories,
        section: original,
      ),
    );
    if (edited == null) return;
    setState(() => _sections = [
      for (var i = 0; i < _sections.length; i++)
        if (i == index) edited else _sections[i],
    ]);
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _sections.length) return;
    setState(() {
      final next = [..._sections];
      final item = next.removeAt(index);
      next.insert(target, item);
      _sections = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 620,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.page == null ? '新建页面' : '编辑页面',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: LcbColors.text,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(
                      CupertinoIcons.xmark,
                      size: 16,
                      color: LcbColors.textTertiary,
                    ),
                    splashRadius: 16,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '页面名称',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<AppIcon>>(
                future: loadAppIcons(),
                builder: (context, snapshot) {
                  final icons = snapshot.data ?? const <AppIcon>[];
                  return DropdownButtonFormField<String>(
                    initialValue: _iconId,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: '页面图标',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('使用默认图标'),
                      ),
                      for (final icon in icons)
                        DropdownMenuItem(
                          value: icon.id,
                          child: Text(icon.name),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _iconId = value ?? ''),
                  );
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _translucent,
                title: const Text('页面外观', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '页面底色会变成半透明，背景图从下面透出来；首页的封面、剧照等内容仍盖在背景图上面。只保存在本机。',
                  style: TextStyle(fontSize: 11.5),
                ),
                onChanged: (value) => setState(() => _translucent = value),
              ),
              const SizedBox(height: 8),
              const _SectionLabel('组件区域'),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < _sections.length; i++) ...[
                        _SectionRow(
                          section: _sections[i],
                          canMoveUp: i > 0,
                          canMoveDown: i < _sections.length - 1,
                          onEdit: () => _editSection(i),
                          onUp: () => _move(i, -1),
                          onDown: () => _move(i, 1),
                          onDelete: () =>
                              setState(() => _sections.removeAt(i)),
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (_sections.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            '这个页面还没有组件',
                            style: TextStyle(
                              fontSize: 13,
                              color: LcbColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _addSection,
                icon: const Icon(CupertinoIcons.add, size: 15),
                label: const Text('添加组件区域'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    style: const TextStyle(fontSize: 12, color: LcbColors.sysRed),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(onPressed: _save, child: const Text('保存')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: LcbColors.textSecondary),
    ),
  );
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.section,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onUp,
    required this.onDown,
    required this.onDelete,
  });

  final PageSection section;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = section.title.trim().isEmpty
        ? section.categoryName
        : section.title.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: LcbColors.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onEdit,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? '未命名区域' : title,
                    style: const TextStyle(fontSize: 13.5, color: LcbColors.text),
                  ),
                  Text(
                    '${section.view.label} · ${section.source.label}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: LcbColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _iconButton(CupertinoIcons.up_arrow, onUp, canMoveUp),
          _iconButton(CupertinoIcons.down_arrow, onDown, canMoveDown),
          _iconButton(CupertinoIcons.trash, onDelete, true),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap, bool enabled) =>
      IconButton(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 15),
        splashRadius: 14,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      );
}

class _SectionEditor extends StatefulWidget {
  const _SectionEditor({required this.categories, required this.section});

  final List<SpiderClass> categories;
  final PageSection section;

  @override
  State<_SectionEditor> createState() => _SectionEditorState();
}

class _SectionEditorState extends State<_SectionEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.section.title,
  );
  late SectionView _view = widget.section.view;
  late SectionSource _source = widget.section.source;
  late String _categoryId = widget.section.categoryId;
  late final List<WidgetInfo> _widgets = WidgetCenter.widgets(
    StoreScope.of(context),
  );
  late String _widgetId = widget.section.widgetId.isNotEmpty
      ? widget.section.widgetId
      : (_widgets.isNotEmpty ? _widgets.first.id : '');
  late String _moduleId = widget.section.moduleId.isNotEmpty
      ? widget.section.moduleId
      : (_widgets.isNotEmpty && _widgets.first.modules.isNotEmpty
          ? _widgets.first.modules.first.id
          : '');

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories;
    final selectedCategory = categories.any((c) => c.typeId == _categoryId)
        ? _categoryId
        : (categories.isNotEmpty ? categories.first.typeId : null);
    return AlertDialog(
      title: const Text('组件区域'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: '组件标题（可留空）',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SectionView>(
              initialValue: _view,
              decoration: const InputDecoration(
                labelText: '展示方式',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final view in SectionView.values)
                  DropdownMenuItem(value: view, child: Text(view.label)),
              ],
              onChanged: (value) => setState(() => _view = value ?? _view),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SectionSource>(
              initialValue: _source,
              decoration: const InputDecoration(
                labelText: '数据来自',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final source in SectionSource.values)
                  DropdownMenuItem(
                    value: source,
                    child: Text(
                      source == SectionSource.tmdb
                          ? '${source.label}（还没接）'
                          : source.label,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _source = value ?? _source),
            ),
            if (_source == SectionSource.category) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedCategory,
                decoration: const InputDecoration(
                  labelText: '资源分类',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final category in categories)
                    DropdownMenuItem(
                      value: category.typeId,
                      child: Text(category.name),
                    ),
                ],
                onChanged: (value) => setState(() => _categoryId = value ?? ''),
              ),
            ],
            if (_source == SectionSource.widget) ...[
              const SizedBox(height: 12),
              if (_widgets.isEmpty)
                const Text(
                  '还没有导入组件仓库。可以在 设置 → 自定义页面 → 组件仓库 里导入。',
                  style: TextStyle(fontSize: 12, color: LcbColors.textSecondary),
                )
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: _widgets.any((w) => w.id == _widgetId)
                      ? _widgetId
                      : _widgets.first.id,
                  decoration: const InputDecoration(
                    labelText: '组件',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final widget in _widgets)
                      DropdownMenuItem(
                        value: widget.id,
                        child: Text(widget.displayName),
                      ),
                  ],
                  onChanged: (value) {
                    final picked = _widgets.firstWhere(
                      (widget) => widget.id == value,
                      orElse: () => _widgets.first,
                    );
                    setState(() {
                      _widgetId = picked.id;
                      _moduleId = picked.modules.isNotEmpty
                          ? picked.modules.first.id
                          : '';
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _moduleId,
                  decoration: const InputDecoration(
                    labelText: '数据源',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final module in _widgets
                        .firstWhere(
                          (widget) => widget.id == _widgetId,
                          orElse: () => _widgets.first,
                        )
                        .modules)
                      DropdownMenuItem(
                        value: module.id,
                        child: Text(module.title),
                      ),
                  ],
                  onChanged: (value) => setState(() => _moduleId = value ?? ''),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            final category = categories.firstWhere(
              (candidate) => candidate.typeId == _categoryId,
              orElse: () => const SpiderClass(typeId: '', name: ''),
            );
            Navigator.of(context).pop(
              widget.section.copyWith(
                title: _title.text.trim(),
                view: _view,
                source: _source,
                categoryId: _source == SectionSource.category
                    ? category.typeId
                    : '',
                categoryName: _source == SectionSource.category
                    ? category.name
                    : '',
                widgetId: _source == SectionSource.widget ? _widgetId : '',
                moduleId: _source == SectionSource.widget ? _moduleId : '',
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
