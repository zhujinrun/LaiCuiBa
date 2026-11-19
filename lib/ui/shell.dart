import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/demo_data.dart';
import 'pages/common_pages.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'page_header.dart';
import 'widgets/shell_header.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  LcbPage _page = LcbPage.home;
  final _header = LcbPageHeader('首页');

  static const _titles = {
    LcbPage.home: '首页',
    LcbPage.resources: '资源',
    LcbPage.favorites: '收藏',
    LcbPage.history: '历史',
    LcbPage.settings: '设置',
  };

  @override
  void dispose() {
    _header.dispose();
    super.dispose();
  }

  void _select(LcbPage page) {
    setState(() => _page = page);
    _header.reset(_titles[page]!);
  }

  Widget _body() {
    switch (_page) {
      case LcbPage.home:
        return const HomePage();
      case LcbPage.resources:
        return const ResourcesPage();
      case LcbPage.favorites:
        return const FavoritesPage();
      case LcbPage.history:
        return const HistoryPage();
      case LcbPage.settings:
        return const SettingsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LcbColors.surface,
      body: LcbPageHeaderScope(
        controller: _header,
        child: Column(
          children: [
            ShellHeader(content: _HeaderContent(page: _page)),
            Expanded(
              child: Row(
                children: [
                  _Sidebar(current: _page, onSelect: _select),
                  Expanded(child: _body()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, required this.onSelect});

  final LcbPage current;
  final ValueChanged<LcbPage> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: LcbMetrics.sidebarWidth,
      decoration: const BoxDecoration(
        color: LcbColors.page,
        border: Border(right: BorderSide(color: Color(0xFFEDEDF0))),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        children: [
          for (final (label, items) in navGroups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: LcbColors.textTertiary,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            for (final (icon, text, page) in items)
              _NavItem(
                icon: icon,
                text: text,
                selected: page == current,
                onTap: () => onSelect(page),
              ),
          ],
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bg = selected
        ? LcbColors.primaryContainer
        : (_hover ? LcbColors.hover : Colors.transparent);
    final fg = selected ? LcbColors.onPrimaryContainer : LcbColors.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: selected ? LcbColors.primary : LcbColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  widget.text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderContent extends StatelessWidget {
  const _HeaderContent({required this.page});

  final LcbPage page;

  @override
  Widget build(BuildContext context) {
    final header = LcbPageHeaderScope.of(context);
    final onBack = header.onBack;

    return Padding(
      padding: const EdgeInsets.fromLTRB(42, 0, 8, 0),
      child: Row(
        children: [
          if (onBack != null) ...[
            _BackButton(onTap: onBack),
            const SizedBox(width: 6),
          ],
          Text(
            header.title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: LcbColors.text,
            ),
          ),
          // Source chips belong to the home feed only; other pages have their
          // own contextual controls in the original.
          if (page == LcbPage.home) ...[
            const SizedBox(width: 22),
            const _SourceChip(label: '豆儿猫源'),
            const SizedBox(width: 8),
            const _SourceChip(label: '[直] 荐片'),
            const SizedBox(width: 8),
            _IconGhost(icon: Icons.dashboard_customize_outlined, onTap: () {}),
          ],
          const Expanded(child: HeaderDragGap()),
          const _SearchBox(),
        ],
      ),
    );
  }
}

class _BackButton extends StatefulWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hover ? LcbColors.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.arrow_back,
            size: 18,
            color: LcbColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SourceChip extends StatefulWidget {
  const _SourceChip({required this.label});

  final String label;

  @override
  State<_SourceChip> createState() => _SourceChipState();
}

class _SourceChipState extends State<_SourceChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _hover ? LcbColors.hover : LcbColors.page,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(
              widget.label,
              style: const TextStyle(fontSize: 12, color: LcbColors.text),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: LcbColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _IconGhost extends StatefulWidget {
  const _IconGhost({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_IconGhost> createState() => _IconGhostState();
}

class _IconGhostState extends State<_IconGhost> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hover ? LcbColors.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(widget.icon, size: 17, color: LcbColors.textSecondary),
        ),
      ),
    );
  }
}

class _SearchBox extends StatefulWidget {
  const _SearchBox();

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        width: 232,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _hover ? const Color(0xFFE8E8EC) : LcbColors.searchFill,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 16, color: LcbColors.textSecondary),
            const SizedBox(width: 8),
            const Text(
              '搜索...',
              style: TextStyle(fontSize: 12.5, color: LcbColors.textSecondary),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Ctrl K',
                style: TextStyle(fontSize: 10, color: LcbColors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
