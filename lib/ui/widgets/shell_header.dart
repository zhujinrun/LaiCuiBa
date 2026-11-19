import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/app_info.dart';
import '../../core/theme.dart';

/// The single 60px strip at the top of the window.
///
/// In the original the brand mark, the page title and the window buttons all
/// sit on one row, and the hairline under it starts where the sidebar ends.
/// Splitting this into a separate title bar plus a page bar pushed every page
/// down by 34px, so the two are composed here instead.
class ShellHeader extends StatefulWidget {
  const ShellHeader({super.key, required this.content});

  /// Page-specific controls: back button, title, filters, search.
  final Widget content;

  @override
  State<ShellHeader> createState() => _ShellHeaderState();
}

class _ShellHeaderState extends State<ShellHeader> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    try {
      windowManager.addListener(this);
      _syncMaximized();
    } catch (_) {
      // Widget tests run without a native window; chrome is inert there.
    }
  }

  @override
  void dispose() {
    try {
      windowManager.removeListener(this);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    try {
      final m = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = m);
    } catch (_) {}
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  void _toggleMaximize() {
    if (_maximized) {
      windowManager.unmaximize();
    } else {
      windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: LcbMetrics.headerHeight,
      child: Row(
        children: [
          _DragArea(
            onDoubleTap: _toggleMaximize,
            child: Container(
              width: LcbMetrics.sidebarWidth,
              padding: const EdgeInsets.only(left: 22),
              alignment: Alignment.centerLeft,
              color: LcbColors.page,
              child: const Text(
                LcbAppInfo.name,
                style: TextStyle(
                  fontFamily: LcbText.body,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6E6E75),
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: LcbColors.surface,
                border: Border(
                  bottom: BorderSide(color: LcbColors.topBarBorder),
                ),
              ),
              child: Row(
                children: [
                  Expanded(child: widget.content),
                  _WinButton(
                    icon: Icons.remove,
                    onTap: () => windowManager.minimize(),
                  ),
                  _WinButton(
                    icon: _maximized ? Icons.filter_none : Icons.crop_square,
                    iconSize: 13,
                    onTap: _toggleMaximize,
                  ),
                  _WinButton(
                    icon: Icons.close,
                    danger: true,
                    onTap: () => windowManager.close(),
                  ),
                  const SizedBox(width: 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Drag handle for the frameless window; double-click toggles maximise.
class _DragArea extends StatelessWidget {
  const _DragArea({required this.child, required this.onDoubleTap});

  final Widget child;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: onDoubleTap,
      child: child,
    );
  }
}

/// A stretch of the header that only drags the window.
class HeaderDragGap extends StatelessWidget {
  const HeaderDragGap({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () => windowManager.isMaximized().then((v) {
        if (v) {
          windowManager.unmaximize();
        } else {
          windowManager.maximize();
        }
      }),
      child: const SizedBox(height: LcbMetrics.headerHeight),
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({
    required this.icon,
    required this.onTap,
    this.danger = false,
    this.iconSize = 15,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  final double iconSize;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (_hover) {
      bg = widget.danger ? const Color(0xFFE81123) : const Color(0xFFE8E8EC);
      fg = widget.danger ? Colors.white : LcbColors.text;
    } else {
      bg = Colors.transparent;
      fg = LcbColors.textSecondary;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 44,
          height: LcbMetrics.headerHeight,
          color: bg,
          child: Icon(widget.icon, size: widget.iconSize, color: fg),
        ),
      ),
    );
  }
}
