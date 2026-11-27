import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 原版「播放内核」面板：MPV / ExoPlayer / MDK。
/// Windows 构建只带 mpv，另外两项照原版摆出来并写明平台限制。
Future<void> showKernelDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => AlertDialog(
    backgroundColor: const Color(0xF21C1C1E),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    title: const Text(
      '播放内核',
      style: TextStyle(fontSize: 15, color: Colors.white),
    ),
    content: const SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _KernelRow(
            label: 'MPV',
            detail: '兼容格式最广，支持 PGS / ASS 字幕',
            selected: true,
          ),
          _KernelRow(
            label: 'ExoPlayer',
            detail: '仅 Android / iOS 可用',
            enabled: false,
          ),
          _KernelRow(
            label: 'MDK',
            detail: 'libmdk，低开销并支持 FFmpeg 软解',
            enabled: false,
          ),
          SizedBox(height: 4),
          Text(
            '从当前进度继续播放。杜比 P5 出现紫绿画面时用 ExoPlayer + 硬解；不同内核的音轨、字幕能力可能不同。',
            style: TextStyle(fontSize: 11.5, color: LcbColors.textSecondary),
          ),
        ],
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

class _KernelRow extends StatelessWidget {
  const _KernelRow({
    required this.label,
    required this.detail,
    this.selected = false,
    this.enabled = true,
  });

  final String label;
  final String detail;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0x33C8B6FF) : const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: enabled ? Colors.white : LcbColors.textTertiary,
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: enabled ? LcbColors.textSecondary : LcbColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            const Icon(Icons.check, size: 18, color: Color(0xFFC8B6FF)),
        ],
      ),
    ),
  );
}
