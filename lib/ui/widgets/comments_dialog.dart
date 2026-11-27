import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 原版顶栏的「评论」抽屉。Bangumi / 豆瓣 两个来源目前都没有真实接口，
/// 所以只摆出原版的外壳和空态，不写死评论、不回落演示数据。
Future<void> showCommentsDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _CommentsDialog(),
);

class _CommentsDialog extends StatefulWidget {
  const _CommentsDialog();

  @override
  State<_CommentsDialog> createState() => _CommentsDialogState();
}

class _CommentsDialogState extends State<_CommentsDialog> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: const Color(0xF21C1C1E),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: SizedBox(
      width: 420,
      height: 560,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '评论',
                  style: TextStyle(fontSize: 15, color: Colors.white),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 17),
                  color: LcbColors.textSecondary,
                  splashRadius: 18,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Tab(
                  label: 'Bangumi',
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                const SizedBox(width: 8),
                _Tab(
                  label: '豆瓣',
                  selected: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
                const Spacer(),
                const Text(
                  '热度',
                  style: TextStyle(fontSize: 12, color: LcbColors.textSecondary),
                ),
                const SizedBox(width: 8),
                const Text(
                  '时间',
                  style: TextStyle(fontSize: 12, color: LcbColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x22FFFFFF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '正在 ${_tab == 0 ? 'Bangumi' : '豆瓣'} 查找作品...',
                style: const TextStyle(fontSize: 12, color: LcbColors.textSecondary),
              ),
            ),
            const Spacer(),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '${_tab == 0 ? 'Bangumi' : '豆瓣'} 评论需要接入对应接口；当前没有配置，不显示未经核实的内容。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: LcbColors.textTertiary,
                  ),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFC8B6FF) : const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: selected ? Colors.black : LcbColors.textSecondary,
        ),
      ),
    ),
  );
}
