import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/app_info.dart';
import '../../core/theme.dart';

/// Frameless window chrome, drawn by us to match the original's flat white bar.
class TitleBar extends StatefulWidget {
  const TitleBar({super.key});

  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> with WindowListener {
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => windowManager.startDragging(),
            onDoubleTap: () => _toggleMaximize(),
            child: Container(
              width: LcbMetrics.sidebarWidth,
              height: 34,
              padding: const EdgeInsets.only(left: 22),
              alignment: Alignment.centerLeft,
              decoration: const BoxDecoration(
                color: LcbColors.page,
                border: Border(right: BorderSide(color: Color(0xFFEDEDF0))),
              ),
              child: const Text(
                LcbAppInfo.name,
                style: TextStyle(
                  fontFamily: LcbText.body,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6E6E75),
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () => _toggleMaximize(),
            ),
          ),
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
    );
  }

  void _toggleMaximize() {
    if (_maximized) {
      windowManager.unmaximize();
    } else {
      windowManager.maximize();
    }
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
          height: 34,
          color: bg,
          child: Icon(widget.icon, size: widget.iconSize, color: fg),
        ),
      ),
    );
  }
}
