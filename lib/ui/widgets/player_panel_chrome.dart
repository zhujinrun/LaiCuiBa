import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 播放页右下角那些浮层（字幕 / 轨道 / 画面比例 / 画面调节 / 选集）共用的外壳。
///
/// 这些面板原来各写一份 Container + 装饰 + 滚动区，宽度和圆角也是各写一遍的
/// 数字；拆成「字幕 / 比例 / 画面」三个之后就是五份，改一次样式要改五处。
/// 外壳只负责「长什么样」，内容仍然由各自的面板决定。
class PlayerPanelShell extends StatelessWidget {
  const PlayerPanelShell({
    super.key,
    required this.child,
    this.width = 300,
    this.scrollable = true,
  });

  final Widget child;
  final double width;

  /// 选集这类自己管滚动的面板传 false，免得滚动条套滚动条。
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    // 一行 34、一组标题 24。窗口矮的时候跟着收，剩下的靠滚动，而不是把最后
    // 几行切在屏幕外。
    final screen = MediaQuery.maybeOf(context)?.size.height ?? 720;
    final maxHeight = (screen - 220).clamp(180.0, 560.0);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [child],
    );
    return Container(
      width: width,
      constraints: BoxConstraints(maxHeight: maxHeight),
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
      child: scrollable
          ? SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: body,
            )
          : body,
    );
  }
}

/// 面板里的小组标题（「线路」「画质」「字幕」…）。
class PanelGroupHeader extends StatelessWidget {
  const PanelGroupHeader(this.text, {super.key});

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

/// 面板里可选的一行：主文字 + 可选的右侧灰字 + 选中打勾。
class PanelRow extends StatefulWidget {
  const PanelRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
    this.subtitle,
  });

  final String label;

  /// 右侧的灰色说明（编码、分辨率、声道…）。
  final String? detail;

  /// 主文字下面的一行小字，用来说明这一档是什么。
  final String? subtitle;

  final bool selected;
  final VoidCallback onTap;

  @override
  State<PanelRow> createState() => _PanelRowState();
}

class _PanelRowState extends State<PanelRow> {
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
          // 有副标题的这一行要有两行的高度，否则会把它挤成省略号。
          constraints: const BoxConstraints(minHeight: 34),
          padding: EdgeInsets.fromLTRB(
            14,
            widget.subtitle == null ? 0 : 7,
            14,
            widget.subtitle == null ? 0 : 7,
          ),
          color: _hover ? const Color(0x14FFFFFF) : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: widget.subtitle == null
                    ? Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: widget.selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: color,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
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
                            widget.subtitle!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                        ],
                      ),
              ),
              if (widget.detail != null) ...[
                const SizedBox(width: 10),
                Text(
                  widget.detail!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ],
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

/// 面板底部的一行说明文字。
class PanelNote extends StatelessWidget {
  const PanelNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          height: 1.5,
          color: Color(0xFF8E8E93),
        ),
      ),
    );
  }
}
