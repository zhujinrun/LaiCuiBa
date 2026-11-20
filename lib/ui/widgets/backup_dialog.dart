import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/backup.dart';
import '../../services/store.dart';

const _width = 558.0;

/// 备份与恢复: export the local dataset, then list what is on disk and offer it
/// back. Every action here is file-system only -- no network, no account.
Future<void> showBackupDialog(BuildContext context, AppStore store) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => _BackupDialog(store: store),
  );
}

class _BackupDialog extends StatefulWidget {
  const _BackupDialog({required this.store});

  final AppStore store;

  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  List<BackupFile>? _files;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final files = await LcbBackup.list();
    if (!mounted) return;
    setState(() => _files = files);
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await LcbBackup.write(widget.store);
      await _reload();
      if (!mounted) return;
      _toast('已备份到 ${file.name}（${file.sizeLabel}）');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '备份失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(BackupFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x78000000),
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '恢复这个备份？',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '当前的源、站点开关、收藏与观看历史会被 ${file.name} 覆盖，无法撤销。',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('恢复', style: TextStyle(color: LcbColors.sysRed)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await LcbBackup.restore(widget.store, file.path);
      if (!mounted) return;
      _toast('已从 ${file.name} 恢复');
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '恢复失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(BackupFile file) async {
    await LcbBackup.delete(file);
    await _reload();
    if (mounted) _toast('已删除 ${file.name}');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: _width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '备份与恢复',
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
              const SizedBox(height: 6),
              Text(
                '备份包含源与站点开关、收藏、观看历史和设置。'
                '文件保存在 ${LcbBackup.directory().path}',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: LcbColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _PrimaryButton(
                    label: '立即备份',
                    busy: _busy,
                    onTap: _busy ? null : _export,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '本机共 ${widget.store.sources.length} 个源 · '
                    '${widget.store.siteCount} 个站点 · '
                    '${widget.store.favorites.length} 条收藏 · '
                    '${widget.store.history.length} 条历史',
                    style: const TextStyle(
                      fontSize: 12,
                      color: LcbColors.textTertiary,
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: LcbColors.sysRed,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                constraints: const BoxConstraints(
                  maxHeight: 264,
                  minHeight: 96,
                ),
                decoration: BoxDecoration(
                  color: LcbColors.card,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: files == null
                    ? const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: LcbColors.primaryDim,
                          ),
                        ),
                      )
                    : files.isEmpty
                    ? const Center(
                        child: Text(
                          '还没有备份',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: LcbColors.textTertiary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: files.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          indent: 12,
                          endIndent: 12,
                          color: LcbColors.cardDivider,
                        ),
                        itemBuilder: (_, index) => _FileRow(
                          file: files[index],
                          enabled: !_busy,
                          onRestore: () => _restore(files[index]),
                          onDelete: () => _delete(files[index]),
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

class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.file,
    required this.enabled,
    required this.onRestore,
    required this.onDelete,
  });

  final BackupFile file;
  final bool enabled;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        color: _hover ? Colors.black.withValues(alpha: 0.025) : null,
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.archivebox,
              size: 16,
              color: LcbColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: LcbColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatTime(file.modified)} · ${file.sizeLabel}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: LcbColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: widget.enabled ? widget.onRestore : null,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('恢复', style: TextStyle(fontSize: 12.5)),
            ),
            IconButton(
              onPressed: widget.enabled ? widget.onDelete : null,
              tooltip: '删除这个备份',
              splashRadius: 14,
              iconSize: 15,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              icon: const Icon(
                CupertinoIcons.trash,
                color: LcbColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? LcbColors.primaryContainer : LcbColors.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          busy ? '处理中…' : label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: onTap == null ? LcbColors.primaryDim : Colors.white,
          ),
        ),
      ),
    );
  }
}
