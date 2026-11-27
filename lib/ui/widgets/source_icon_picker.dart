import 'dart:io';

import 'package:file_selector/file_selector.dart'
    show XTypeGroup, openFile;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/app_icons.dart';
import '../../services/icon_packs.dart';

/// 「更换图标」：the bundled 图标包, grouped the way the pack groups itself.
///
/// Picking one saves immediately and closes — the card behind updates through
/// the store, so there is no separate 确认 step to forget.
Future<void> showSourceIconPicker(BuildContext context, SourceInfo source) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => _SourceIconPicker(source: source),
  );
}

class _SourceIconPicker extends StatefulWidget {
  const _SourceIconPicker({required this.source});

  final SourceInfo source;

  @override
  State<_SourceIconPicker> createState() => _SourceIconPickerState();
}

class _SourceIconPickerState extends State<_SourceIconPicker> {
  final Future<List<AppIcon>> _icons = loadAppIcons();
  final List<IconPack> _packs = IconPacks.load();
  final TextEditingController _search = TextEditingController();
  String _filter = '';
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pick(String iconId) async {
    await StoreScope.of(context).setSourceIcon(
      widget.source.id,
      iconId,
      iconPath: '',
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 图标包 / 本地图片里的图标先复制一份到这个源名下，再写进 store。
  /// 包以后被删掉也不会让资源卡片指向一个不存在的路径。
  Future<void> _pickPath(String path) async {
    try {
      final stored = await IconPacks.applyFile(widget.source.id, path);
      if (!mounted) return;
      await StoreScope.of(context).setSourceIcon(
        widget.source.id,
        '',
        iconPath: stored,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on IconPackException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  Future<void> _pickPackIcon(IconPack pack, String file) async {
    try {
      final stored = await IconPacks.applyPackIcon(widget.source.id, pack, file);
      if (!mounted) return;
      await StoreScope.of(context).setSourceIcon(
        widget.source.id,
        '',
        iconPath: stored,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on IconPackException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  Future<void> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '图片',
          extensions: ['webp', 'png', 'jpg', 'jpeg', 'gif', 'bmp'],
        ),
      ],
    );
    if (file != null) await _pickPath(file.path);
  }

  bool _matches(String name) =>
      _filter.isEmpty || name.toLowerCase().contains(_filter);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '更换图标',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      color: LcbColors.text,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        CupertinoIcons.xmark,
                        size: 16,
                        color: LcbColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: '搜索图标名称',
                    prefixIcon: Icon(CupertinoIcons.search, size: 16),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) =>
                      setState(() => _filter = value.trim().toLowerCase()),
                ),
              ),
              const SizedBox(height: 10),
              _DefaultRow(
                selected: widget.source.iconId.isEmpty &&
                    widget.source.iconPath.isEmpty,
                onTap: () => _pick(''),
              ),
              const SizedBox(height: 6),
              _ChoiceRow(
                icon: CupertinoIcons.photo,
                label: '选择图标文件',
                onTap: _pickFile,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text(
                    _error!,
                    style: const TextStyle(fontSize: 12, color: LcbColors.sysRed),
                  ),
                ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_packs.isNotEmpty) ...[
                        const _SectionLabel('图标包'),
                        for (final pack in _packs) ...[
                          _SectionLabel(
                            pack.name.isEmpty ? '未命名图标包' : pack.name,
                          ),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final file in pack.files)
                                if (_matches(file))
                                  _FileIconTile(
                                    pack: pack,
                                    file: file,
                                    selected: widget.source.iconPath.endsWith(file),
                                    onTap: () => _pickPackIcon(pack, file),
                                  ),
                            ],
                          ),
                        ],
                      ],
                      const _SectionLabel('内置图标'),
                      FutureBuilder<List<AppIcon>>(
                        future: _icons,
                        builder: (context, snapshot) {
                          final icons = (snapshot.data ?? const <AppIcon>[])
                              .where((icon) => _matches(icon.name))
                              .toList();
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 28),
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
                          if (icons.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 28),
                              child: Text(
                                '没有找到图标',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: LcbColors.textSecondary,
                                ),
                              ),
                            );
                          }
                          final groups = groupAppIcons(icons);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final entry in groups.entries) ...[
                                _SectionLabel(entry.key),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    for (final icon in entry.value)
                                      _IconTile(
                                        icon: icon,
                                        selected: icon.id == widget.source.iconId,
                                        onTap: () => _pick(icon.id),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「使用默认图标」 — clears the pick so the type glyph comes back.
class _DefaultRow extends StatelessWidget {
  const _DefaultRow({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? LcbColors.primaryContainer : LcbColors.card,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(
                CupertinoIcons.square_grid_2x2,
                size: 16,
                color: LcbColors.textSecondary,
              ),
              const SizedBox(width: 10),
              const Text(
                '使用默认图标',
                style: TextStyle(fontSize: 13.5, color: LcbColors.text),
              ),
              const Spacer(),
              if (selected)
                const Icon(
                  CupertinoIcons.checkmark_alt,
                  size: 14,
                  color: LcbColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconTile extends StatefulWidget {
  const _IconTile({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final AppIcon icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_IconTile> createState() => _IconTileState();
}

class _IconTileState extends State<_IconTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Tooltip(
          message: widget.icon.name,
          waitDuration: const Duration(milliseconds: 400),
          child: Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: LcbColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.selected
                    ? LcbColors.primary
                    : _hover
                    ? const Color(0xFFBBD2F5)
                    : Colors.transparent,
                width: widget.selected ? 2 : 1,
              ),
            ),
            child: Image.asset(
              widget.icon.assetPath,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                CupertinoIcons.photo,
                size: 18,
                color: LcbColors.textTertiary,
              ),
            ),
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 0, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: LcbColors.textTertiary,
        ),
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: LcbColors.card,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: LcbColors.textSecondary),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(fontSize: 13.5, color: LcbColors.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileIconTile extends StatelessWidget {
  const _FileIconTile({
    required this.pack,
    required this.file,
    required this.selected,
    required this.onTap,
  });

  final IconPack pack;
  final String file;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final path = '${IconPacks.directory().path}${Platform.pathSeparator}packs'
        '${Platform.pathSeparator}${pack.id}${Platform.pathSeparator}$file';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Tooltip(
          message: file,
          waitDuration: const Duration(milliseconds: 400),
          child: Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: LcbColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? LcbColors.primary
                    : const Color(0xFFBBD2F5),
                width: selected ? 2 : 1,
              ),
            ),
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                CupertinoIcons.photo,
                size: 18,
                color: LcbColors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
