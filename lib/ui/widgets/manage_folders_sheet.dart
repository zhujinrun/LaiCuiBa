import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/store.dart';

/// 管理收藏夹 dialog: lists the folders with rename / delete, and a "新建收藏夹"
/// action that prompts for a name. Wired to the folder glyph on the favourites
/// header. Deleting a folder returns its favourites to the uncategorised pool.
Future<void> showManageFoldersSheet(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ManageFoldersDialog(),
  );
}

class _ManageFoldersDialog extends StatefulWidget {
  const _ManageFoldersDialog();

  @override
  State<_ManageFoldersDialog> createState() => _ManageFoldersDialogState();
}

class _ManageFoldersDialogState extends State<_ManageFoldersDialog> {
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final folders = store.favoriteFolders;

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: const Text(
        '管理收藏夹',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final folder in folders)
              _FolderRow(
                folder: folder,
                onRename: () => _rename(store, folder),
                onDelete: () => store.deleteFavoriteFolder(folder.id),
              ),
            if (folders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '还没有收藏夹',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: LcbColors.settingsQuiet),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _create(store),
          child: const Text(
            '新建收藏夹',
            style: TextStyle(color: LcbColors.primaryDim),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '完成',
            style: TextStyle(color: LcbColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Future<void> _create(AppStore store) async {
    final name = await _promptName(context, title: '新建收藏夹');
    if (name == null || name.isEmpty) return;
    await store.createFavoriteFolder(name);
  }

  Future<void> _rename(AppStore store, FavoriteFolder folder) async {
    final name = await _promptName(
      context,
      title: '重命名',
      initial: folder.name,
    );
    if (name == null || name.isEmpty) return;
    await store.renameFavoriteFolder(folder.id, name);
  }
}

/// A single folder row: name on the left, rename + delete glyphs on the right.
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.onRename,
    required this.onDelete,
  });

  final FavoriteFolder folder;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          CupertinoIcons.folder,
          size: 16,
          color: LcbColors.textSecondary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, color: LcbColors.text),
          ),
        ),
        IconButton(
          onPressed: onRename,
          icon: const Icon(
            CupertinoIcons.pencil,
            size: 16,
            color: LcbColors.textSecondary,
          ),
          tooltip: '重命名',
        ),
        IconButton(
          onPressed: onDelete,
          icon: const Icon(
            CupertinoIcons.trash,
            size: 16,
            color: LcbColors.sysRed,
          ),
          tooltip: '删除',
        ),
      ],
    );
  }
}

/// Prompts for a folder name via a small text dialog. Returns null on cancel.
Future<String?> _promptName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(fontSize: 14, color: LcbColors.text),
        decoration: const InputDecoration(
          hintText: '收藏夹名称',
          isDense: true,
        ),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: LcbColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text(
            '确定',
            style: TextStyle(color: LcbColors.primaryDim),
          ),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
