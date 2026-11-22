import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/picture.dart';

/// 播放页右下角弹出的「画面」面板：画面比例 + 画面调节。
///
/// 对齐原版 BieCuiLe 的两个画面能力——比例六档（原始/拉伸全屏/拉伸铺满/宽度
/// 拉伸/高度拉伸/裁剪铺满），调节五个量（亮度/对比度/饱和度/色相/伽马）。
/// 比例立即生效（改 `BoxFit`），调节滑一下改一下 mpv 属性。
class PicturePanel extends StatelessWidget {
  const PicturePanel({
    super.key,
    required this.mode,
    required this.adjust,
    required this.onMode,
    required this.onAdjust,
  });

  final AspectMode mode;
  final PictureAdjust adjust;
  final ValueChanged<AspectMode> onMode;
  final ValueChanged<PictureAdjust> onAdjust;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xF21C1C1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1FFFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _GroupHeader('画面比例'),
            for (final m in AspectMode.values)
              _AspectRow(
                label: m.label,
                detail: m.description,
                selected: m == mode,
                onTap: () => onMode(m),
              ),
            const _GroupHeader('画面调节'),
            _Slider(
              label: '亮度',
              value: adjust.brightness,
              onChanged: (v) => onAdjust(adjust.copyWith(brightness: v)),
            ),
            _Slider(
              label: '对比度',
              value: adjust.contrast,
              onChanged: (v) => onAdjust(adjust.copyWith(contrast: v)),
            ),
            _Slider(
              label: '饱和度',
              value: adjust.saturation,
              onChanged: (v) => onAdjust(adjust.copyWith(saturation: v)),
            ),
            _Slider(
              label: '色相',
              value: adjust.hue,
              onChanged: (v) => onAdjust(adjust.copyWith(hue: v)),
            ),
            _Slider(
              label: '伽马',
              value: adjust.gamma,
              onChanged: (v) => onAdjust(adjust.copyWith(gamma: v)),
            ),
            if (!adjust.isNeutral)
              _ResetRow(
                onTap: () => onAdjust(PictureAdjust.none),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text(
                '0% 是原始画面；这里的亮度和屏幕亮度分开',
                style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: Color(0xFF8E8E93),
        ),
      ),
    );
  }
}

class _AspectRow extends StatefulWidget {
  const _AspectRow({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AspectRow> createState() => _AspectRowState();
}

class _AspectRowState extends State<_AspectRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.selected ? LcbColors.primary : Colors.white;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          color: _hover ? const Color(0x14FFFFFF) : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.detail,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.selected) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check, size: 15, color: LcbColors.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: Colors.white),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.toDouble().clamp(-100.0, 100.0),
              min: -100,
              max: 100,
              activeColor: LcbColors.primary,
              inactiveColor: const Color(0x33FFFFFF),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFB8B8BE),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResetRow extends StatelessWidget {
  const _ResetRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        child: const Text(
          '恢复原始画面',
          style: TextStyle(fontSize: 13, color: LcbColors.primary),
        ),
      ),
    );
  }
}
