import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/models.dart';

class FavoritePick {
  const FavoritePick({this.folderId, this.newFolderName});

  final String? folderId;
  final String? newFolderName;
}

/// 换平台：原版会跨源搜同名作品。当前没有跨源搜索服务，给真空态，
/// 不列看起来像结果其实没数据的卡片。
Future<void> showPlatformDialog(BuildContext context, String title) =>
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xF21C1C1E),
        title: Text('换平台 · $title'),
        content: const SizedBox(
          width: 400,
          child: Text(
            '正在搜索其他平台…\n\n当前没有可用的跨源搜索结果。可以在「资源」页切换有这个作品的站点。',
            style: TextStyle(fontSize: 13, color: LcbColors.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );

/// 下载：列出真实集数，但下载引擎未接入，底部按钮明确不可用。
Future<void> showDownloadDialog(BuildContext context, List<String> episodes) =>
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xF21C1C1E),
        title: const Text('下载'),
        content: SizedBox(
          width: 420,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '共 ${episodes.length} 集 · 下载引擎尚未接入',
                style: const TextStyle(
                  fontSize: 12,
                  color: LcbColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: episodes.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '${i + 1}. ${episodes[i]}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: LcbColors.text,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );

/// 追更：原版会去 Trakt / Bangumi 匹配。没有账号与接口时不假装匹配成功。
Future<void> showFollowDialog(BuildContext context, String title) =>
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xF21C1C1E),
        title: const Text('追更'),
        content: SizedBox(
          width: 400,
          child: Text(
            '正在匹配「$title」…\n\n没有配置 Trakt / Bangumi 账号，也没有匹配结果。请先到设置里登录对应账号。',
            style: const TextStyle(
              fontSize: 13,
              color: LcbColors.textSecondary,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );

/// 收藏到：原版是收藏夹选择而非直接翻转一个布尔值。
Future<FavoritePick?> showFavoriteFolderDialog(
  BuildContext context,
  List<FavoriteFolder> folders,
) => showDialog<FavoritePick>(
  context: context,
  builder: (_) => _FavoriteFolderDialog(folders: folders),
);

class _FavoriteFolderDialog extends StatefulWidget {
  const _FavoriteFolderDialog({required this.folders});

  final List<FavoriteFolder> folders;

  @override
  State<_FavoriteFolderDialog> createState() => _FavoriteFolderDialogState();
}

class _FavoriteFolderDialogState extends State<_FavoriteFolderDialog> {
  String? _selected;
  bool _creating = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xF21C1C1E),
    title: const Text('收藏到'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final folder in widget.folders)
            ListTile(
              dense: true,
              leading: Icon(
                _selected == folder.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: _selected == folder.id
                    ? LcbColors.primary
                    : LcbColors.textSecondary,
              ),
              title: Text(folder.name),
              onTap: () => setState(() {
                _selected = folder.id;
                _creating = false;
              }),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.create_new_folder, size: 18),
            title: const Text('新建收藏夹'),
            selected: _creating,
            onTap: () => setState(() => _creating = true),
          ),
          if (_creating)
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '收藏夹名称',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
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
          if (_creating) {
            final name = _controller.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop(FavoritePick(newFolderName: name));
          } else {
            Navigator.of(context).pop(FavoritePick(folderId: _selected));
          }
        },
        child: const Text('确定'),
      ),
    ],
  );
}
